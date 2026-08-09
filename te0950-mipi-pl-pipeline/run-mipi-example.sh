#!/usr/bin/env bash
# MIPI Example bring-up for Raspberry Pi Camera Module v2 (IMX219)
set -euo pipefail

MODE="${1:-snapshot}"
DTBO_PATH_VALUE="${DTBO_PATH:-/usr/lib/firmware/mipi-example}"
I2C_BUS="${I2C_BUS:-1}"
I2C_ADDR="${I2C_ADDR:-10}"
WIDTH="${WIDTH:-1920}"
HEIGHT="${HEIGHT:-1080}"
DEV="${DEV:-/dev/media0}"
VIDEO_DEV="${VIDEO_DEV:-/dev/video0}"
BIND_ADDR="${BIND_ADDR:-0.0.0.0}"
BIND_PORT="${BIND_PORT:-5001}"
UDP_HOST="${UDP_HOST:-192.168.0.20}"
UDP_PORT="${UDP_PORT:-5000}"
SDP_OUT="${SDP_OUT:-/tmp/mipi.sdp}"

usage() {
  echo "Usage: $0 [snapshot|video|udp|still]"
  echo "  snapshot|still  capture frames with yavta to /tmp/mipi-snapshot-#.bin"
  echo "  video           stream multipart JPEG over TCP (port ${BIND_PORT})"
  echo "  udp             stream RTP/JPEG over UDP for VLC (needs SDP file)"
  echo
  echo "Env:"
  echo "  UDP_HOST/UDP_PORT   PC IP and UDP port (default ${UDP_HOST}:${UDP_PORT})"
  echo "  WIDTH/HEIGHT        default ${WIDTH}x${HEIGHT}"
  echo "  SDP_OUT             where to write VLC SDP (default ${SDP_OUT})"
  echo
  echo "VLC (udp mode): Media → Open File → mipi.sdp  (NOT rtp:// or udp:// alone)"
}

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

setup_pipeline_named() {
  local sensor csi demosaic csc
  sensor="$(find_entity "imx219")" || sensor=""
  csi="$(find_entity "mipi_csi2_rx_subsystem")" || csi=""
  demosaic="$(find_entity "v_demosaic")" || demosaic=""
  # Do not match "vcap_v_proc_ss_csc output 0"
  csc="$(find_entity "^[0-9a-f]+\\.v_proc_ss$")" || csc=""

  if [[ -z "$sensor" || -z "$csi" ]]; then
    echo "Could not find imx219 / mipi_csi2 entities on $DEV"
    echo "Run: media-ctl -d $DEV -p"
    return 1
  fi

  local fmt_in="SRGGB10_1X10/${WIDTH}x${HEIGHT}"
  local fmt_rgb="RBG888_1X24/${WIDTH}x${HEIGHT}"
  local fmt_out="UYVY8_1X16/${WIDTH}x${HEIGHT}"

  echo "Sensor entity: $sensor"
  echo "CSI entity:    $csi"
  media-ctl --set-v4l2 "'${sensor}':0[fmt:$fmt_in field:none]" -d "$DEV"
  media-ctl --set-v4l2 "'${csi}':0[fmt:$fmt_in field:none]" -d "$DEV"
  media-ctl --set-v4l2 "'${csi}':1[fmt:$fmt_in field:none]" -d "$DEV"

  if [[ -n "$demosaic" ]]; then
    echo "Demosaic:      $demosaic"
    media-ctl --set-v4l2 "'${demosaic}':0[fmt:$fmt_in field:none]" -d "$DEV" || true
    media-ctl --set-v4l2 "'${demosaic}':1[fmt:$fmt_rgb field:none]" -d "$DEV" || true
  fi
  if [[ -n "$csc" ]]; then
    echo "CSC:           $csc"
    media-ctl --set-v4l2 "'${csc}':0[fmt:$fmt_rgb field:none]" -d "$DEV" || true
    media-ctl --set-v4l2 "'${csc}':1[fmt:$fmt_out field:none]" -d "$DEV" || true
  else
    echo "WARNING: VPSS CSC entity not found — capture may fail"
  fi
}

write_vlc_sdp() {
  # VLC needs SDP for RTP JPEG (payload type 26); bare rtp:// URLs fail.
  cat > "$SDP_OUT" <<EOF
v=0
o=- 0 0 IN IP4 ${UDP_HOST}
s=TE0950 MIPI
c=IN IP4 ${UDP_HOST}
t=0 0
m=video ${UDP_PORT} RTP/AVP 26
a=rtpmap:26 JPEG/90000
EOF
  echo "Wrote VLC SDP: $SDP_OUT"
  echo "Copy to PC and open with VLC: Media → Open File → mipi.sdp"
  echo "---- SDP ----"
  cat "$SDP_OUT"
  echo "-------------"
}

load_overlay_if_needed() {
  if find_entity "imx219" >/dev/null 2>&1; then
    echo "Camera already in DT — skipping overlay"
    return 0
  fi

  local ov_path="/sys/kernel/config/device-tree/overlays/cam"
  if [[ -d "$ov_path" ]]; then
    return 0
  fi

  echo "imx219 not in media graph; overlay load skipped (use base DT image)"
  return 0
}

case "$MODE" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac

echo "Using MIPI Example bring-up"
load_overlay_if_needed
setup_pipeline_named

case "$MODE" in
  snapshot|still)
    echo "Snapshot ${WIDTH}x${HEIGHT} from $VIDEO_DEV"
    sleep 2
    rm -f /tmp/mipi-snapshot-*.bin
    yavta -f UYVY -s "${WIDTH}x${HEIGHT}" -c8 -n4 -F=/tmp/mipi-snapshot-#.bin "$VIDEO_DEV"
    ls -lah /tmp/mipi-snapshot-*.bin
    ;;
  video)
    echo "Video TCP JPEG on ${BIND_ADDR}:${BIND_PORT}"
    gst-launch-1.0 v4l2src device="$VIDEO_DEV" io-mode=mmap ! \
      "video/x-raw, width=${WIDTH}, height=${HEIGHT}, format=UYVY" ! \
      jpegenc ! multipartmux ! \
      tcpserversink host="$BIND_ADDR" port="$BIND_PORT" sync=false
    ;;
  udp)
    write_vlc_sdp
    echo "Video RTP/JPEG UDP → ${UDP_HOST}:${UDP_PORT}"
    echo "On PC: open the SDP file in VLC (Media → Open File)"
    sleep 1
    gst-launch-1.0 v4l2src device="$VIDEO_DEV" io-mode=mmap ! \
      "video/x-raw, width=${WIDTH}, height=${HEIGHT}, format=UYVY" ! \
      jpegenc ! rtpjpegpay pt=26 ! \
      udpsink host="$UDP_HOST" port="$UDP_PORT" sync=false
    ;;
  *)
    usage
    exit 1
    ;;
esac
