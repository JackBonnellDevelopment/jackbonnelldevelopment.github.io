SUMMARY = "TE0950 MIPI CSI pipeline self-test"
SECTION = "PETALINUX/apps"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://test-mipi-pipeline.sh file://imx219-overlay.dtbo"

S = "${WORKDIR}"

RDEPENDS:${PN} += "bash v4l-utils yavta i2c-tools"

do_install() {
    install -d ${D}${bindir}
    install -d ${D}${nonarch_base_libdir}/firmware/mipi-example
    install -m 0755 ${S}/test-mipi-pipeline.sh ${D}${bindir}/test-mipi-pipeline
    install -m 0644 ${S}/imx219-overlay.dtbo ${D}${nonarch_base_libdir}/firmware/mipi-example/imx219-overlay.dtbo
}

FILES:${PN} += "${nonarch_base_libdir}/firmware/mipi-example/imx219-overlay.dtbo"
