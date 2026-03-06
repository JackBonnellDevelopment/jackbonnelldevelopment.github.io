SUMMARY = "TPG viewer - display video from /dev/video0 using OpenCV"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS = "opencv"


SRC_URI = "file://tpg-viewer.cpp"
S = "${WORKDIR}"

do_compile() {
    ${CXX} ${CXXFLAGS} -I${STAGING_INCDIR} -I${STAGING_INCDIR}/opencv4 tpg-viewer.cpp \
        -L${STAGING_LIBDIR} -lopencv_core -lopencv_videoio -lopencv_highgui -lopencv_imgproc \
        ${LDFLAGS} -o tpg_viewer
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 tpg_viewer ${D}${bindir}
}
