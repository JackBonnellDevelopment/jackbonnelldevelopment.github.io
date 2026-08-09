#!/usr/bin/env bash
# Quick bring-up test: IMX219 -> MIPI CSI-2 -> PL pipeline -> DDR -> V4L2
set -euo pipefail

DTBO_PATH_VALUE="${DTBO_PATH:-/usr/lib/firmware/mipi-example}"
I2C_BUS="${I2C_BUS:-}"
I2C_ADDR="${I2C_ADDR:-10}"
WIDTH="${WIDTH:-1920}"
HEIGHT="${HEIGHT:-1080}"
DEV="${DEV:-/dev/media0}"
VIDEO_DEV="${VIDEO_DEV:-/dev/video0}"
OUT="${OUT:-/tmp/mipi-pipeline-test-#.bin}"
SKIP_CAPTURE="${SKIP_CAPTURE:-0}"
NBUFS="${NBUFS:-4}"
NFRAMES="${NFRAMES:-8}"

pass=0
fail=0

ok()   { echo "[PASS] $*"; pass=$((pass + 1)); }
bad()  { echo "[FAIL] $*"; fail=$((fail + 1)); }
info() { echo "[INFO] $*"; }

# media-ctl prints "- entity N: name (...)" — return entity name, non-zero if missing
find_entity() {
  local pattern="$1"
  local name
  name="$(media-ctl -d "$DEV" -p 2>/dev/null | awk -v pat="$pattern" '
    /^- entity [0-9]+:/ {
      line=$0
      sub(/^- entity [0-9]+: /, "", line)
      sub(/ \(.*$/, "", line)
      if (line ~ pat) {
        print line
        exit
      }
    }
  ')"
  [[ -n "$name" ]] || return 1
  printf '%s\n' "$name"
}

find_dtbo() {
  local cand
  for cand in \
    "${DTBO_PATH_VALUE}/imx219-overlay.dtbo" \
    /usr/lib/firmware/mipi-example/imx219-overlay.dtbo \
    /lib/firmware/mipi-example/imx219-overlay.dtbo \
    /boot/dtbos/imx219-overlay.dtbo \
    /boot/imx219-overlay.dtbo \
    /run/media/*/dtbos/imx219-overlay.dtbo \
    /run/media/*/imx219-overlay.dtbo
  do
    if [[ -f "$cand" ]]; then
      echo "$cand"
      return 0
    fi
  done
  return 1
}

# Prefer PL xiic (a4010000); treat UU (driver-bound) as present
detect_i2c_bus() {
  if [[ -n "${I2C_BUS}" ]]; then
    echo "$I2C_BUS"
    return 0
  fi
  local bus line
  if command -v i2cdetect >/dev/null 2>&1; then
    # Prefer xiic / a4010000
    bus="$(i2cdetect -l 2>/dev/null | awk '/xiic|a4010000/{print $1; exit}' | sed 's/i2c-//')"
    if [[ -n "$bus" ]]; then
      echo "$bus"
      return 0
    fi
    while read -r line; do
      bus="${line#i2c-}"
      if i2cdetect -y "$bus" 2>/dev/null | grep -Eiq "(^| )${I2C_ADDR}( |$)| UU "; then
        echo "$bus"
        return 0
      fi
    done < <(i2cdetect -l 2>/dev/null | awk '{print $1}')
  fi
  echo "1"
}

i2c_sensor_present() {
  local bus="$1"
  local map
  map="$(i2cdetect -y "$bus" 2>/dev/null || true)"
  # Free addr "10" or driver-claimed "UU" in the 0x10 column
  echo "$map" | grep -Eiq "(^| )${I2C_ADDR}( |$)|[[:space:]]UU[[:space:]]"
}

load_overlay_if_needed() {
  if [[ -c "$DEV" ]] && find_entity "imx219" >/dev/null; then
    info "Camera already present in DT — skipping overlay"
    return 0
  fi

  local ov_path="/sys/kernel/config/device-tree/overlays/cam"
  if [[ -d "$ov_path" ]]; then
    info "Camera overlay already loaded"
    return 0
  fi

  if [[ ! -d /sys/kernel/config/device-tree/overlays ]]; then
    info "OF configfs overlays not available (OK if camera is in base DT)"
    return 0
  fi

  if [[ "$(id -u)" -ne 0 ]]; then
    bad "Need root to load DT overlay (run: sudo test-mipi-pipeline)"
    return 1
  fi

  local dtbo
  if ! dtbo="$(find_dtbo)"; then
    bad "imx219-overlay.dtbo not found"
    return 1
  fi

  info "Loading overlay: $dtbo"
  mkdir -p "$ov_path"
  if ! cat "$dtbo" > "${ov_path}/dtbo" 2>/tmp/dtbo_load.err; then
    bad "Overlay load failed (write error)"
    rm -rf "$ov_path" 2>/dev/null || true
    return 1
  fi
  sleep 1
  local st=""
  [[ -f "${ov_path}/status" ]] && st="$(tr -d '\0' < "${ov_path}/status" 2>/dev/null || true)"
  if [[ "$st" == "applied" ]]; then
    ok "Overlay loaded"
  else
    bad "Overlay load failed (status='${st:-unknown}')"
    rm -rf "$ov_path" 2>/dev/null || true
    return 1
  fi
}

setup_pipeline() {
  local sensor csi demosaic csc
  sensor="$(find_entity "imx219")" || sensor=""
  csi="$(find_entity "mipi_csi2_rx_subsystem")" || csi=""
  demosaic="$(find_entity "v_demosaic")" || demosaic=""
  # Must not match "vcap_v_proc_ss_csc output 0"
  csc="$(find_entity "^[0-9a-f]+\\.v_proc_ss$")" || csc=""

  if [[ -z "$sensor" ]]; then
    bad "IMX219 media entity not found on $DEV"
    return 1
  fi
  ok "Sensor entity: $sensor"

  if [[ -z "$csi" ]]; then
    bad "MIPI CSI-2 RX entity not found on $DEV"
    return 1
  fi
  ok "CSI entity: $csi"

  [[ -n "$demosaic" ]] && ok "Demosaic entity: $demosaic"
  [[ -n "$csc" ]] && ok "CSC entity: $csc"

  # RAW10 path (matches BD); media-ctl media-bus codes
  local fmt_in="SRGGB10_1X10/${WIDTH}x${HEIGHT}"
  local fmt_rgb="RBG888_1X24/${WIDTH}x${HEIGHT}"
  local fmt_out="UYVY8_1X16/${WIDTH}x${HEIGHT}"

  media-ctl --set-v4l2 "'${sensor}':0[fmt:$fmt_in field:none]" -d "$DEV"
  media-ctl --set-v4l2 "'${csi}':0[fmt:$fmt_in field:none]" -d "$DEV"
  media-ctl --set-v4l2 "'${csi}':1[fmt:$fmt_in field:none]" -d "$DEV"

  if [[ -n "$demosaic" ]]; then
    media-ctl --set-v4l2 "'${demosaic}':0[fmt:$fmt_in field:none]" -d "$DEV" || true
    media-ctl --set-v4l2 "'${demosaic}':1[fmt:$fmt_rgb field:none]" -d "$DEV" || true
  fi
  if [[ -n "$csc" ]]; then
    media-ctl --set-v4l2 "'${csc}':0[fmt:$fmt_rgb field:none]" -d "$DEV" || true
    media-ctl --set-v4l2 "'${csc}':1[fmt:$fmt_out field:none]" -d "$DEV" || true
  fi
  ok "Media pipeline configured for ${WIDTH}x${HEIGHT}"
}

echo "=== TE0950 MIPI pipeline test ==="
if [[ "$(id -u)" -ne 0 ]]; then
  info "Not root — media setup may need: sudo test-mipi-pipeline"
fi

info "I2C adapters:"
i2cdetect -l 2>/dev/null || true

I2C_BUS="$(detect_i2c_bus)"
info "Using I2C bus ${I2C_BUS}, sensor addr 0x${I2C_ADDR}"

if command -v i2cdetect >/dev/null 2>&1; then
  if i2c_sensor_present "$I2C_BUS"; then
    ok "IMX219 on i2c-${I2C_BUS} @ 0x${I2C_ADDR} (or UU=driver-bound)"
  elif find_entity "imx219" >/dev/null 2>&1; then
    ok "IMX219 bound via V4L2 (i2c-${I2C_BUS}; i2cdetect may show UU)"
  else
    bad "IMX219 not detected on i2c-${I2C_BUS} @ 0x${I2C_ADDR} (Cam v2 on J15?)"
  fi
else
  bad "i2cdetect not installed"
fi

load_overlay_if_needed || true

if [[ -c "$DEV" ]]; then
  ok "Media device $DEV present"
  info "Media graph (truncated):"
  media-ctl -d "$DEV" -p 2>/dev/null | sed -n '1,80p' || bad "media-ctl -p failed"
  setup_pipeline || true
else
  bad "Media device $DEV missing (camera DT / drivers not up)"
fi

if [[ -c "$VIDEO_DEV" ]]; then
  ok "Video node $VIDEO_DEV present"
else
  if compgen -G '/dev/video*' >/dev/null; then
    VIDEO_DEV="$(ls /dev/video* | head -1)"
    ok "Using video node $VIDEO_DEV"
  else
    bad "Video node /dev/video* missing"
  fi
fi

if [[ "$SKIP_CAPTURE" != "1" ]] && [[ -c "$VIDEO_DEV" ]]; then
  info "Capturing ${NFRAMES}x ${WIDTH}x${HEIGHT} UYVY (nbufs=${NBUFS}) -> ${OUT}"
  sleep 2
  rm -f /tmp/mipi-pipeline-test-*.bin /tmp/frame-*.bin 2>/dev/null || true
  # yavta: -F[=name] ; '#' expands to sequence; device is last arg
  if yavta -f UYVY -s "${WIDTH}x${HEIGHT}" -c"${NFRAMES}" -n"${NBUFS}" -F="${OUT}" "$VIDEO_DEV"; then
    got="$(ls -1 /tmp/mipi-pipeline-test-*.bin /tmp/frame-*.bin 2>/dev/null | head -1 || true)"
    if [[ -n "$got" && -s "$got" ]]; then
      ok "Frame captured: $got ($(stat -c%s "$got") bytes)"
    else
      bad "Capture produced no frame file"
    fi
  else
    bad "yavta capture failed"
  fi
fi

echo
echo "=== Summary: ${pass} passed, ${fail} failed ==="
if [[ "$fail" -eq 0 ]]; then
  echo "RESULT: PASS — MIPI CSI -> DDR pipeline looks OK"
  exit 0
fi
echo "RESULT: FAIL — check camera FFC on J15, DT enablement, and media graph"
exit 1
