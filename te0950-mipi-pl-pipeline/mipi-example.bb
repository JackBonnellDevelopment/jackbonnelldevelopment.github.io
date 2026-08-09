SUMMARY = "TE0950 MIPI Example camera bring-up and UDP stream helper"
SECTION = "PETALINUX/apps"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://run-mipi-example.sh \
           file://mipi.sdp \
"

S = "${WORKDIR}"

RDEPENDS:${PN} += "bash gstreamer1.0 gstreamer1.0-plugins-base gstreamer1.0-plugins-good v4l-utils yavta"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${S}/run-mipi-example.sh ${D}${bindir}/run-mipi-example.sh
    install -d ${D}${datadir}/mipi-example
    install -m 0644 ${S}/mipi.sdp ${D}${datadir}/mipi-example/mipi.sdp
}

FILES:${PN} += "${datadir}/mipi-example"
