/*
 * TPG viewer - display video from /dev/video0 (Xilinx TPG -> vcap) using OpenCV + GStreamer.
 * Example pipeline setup (run once before this program, adjust for your design):
 *   media-ctl -d /dev/media0 -V '"a0010000.v_tpg":0 [fmt:RBG888_1X24/1920x1080 field:none]'
 */

#include <opencv2/core.hpp>
#include <opencv2/videoio.hpp>
#include <opencv2/highgui.hpp>
#include <opencv2/imgproc.hpp>
#include <iostream>
#include <sstream>
#include <csignal>

static volatile int g_running = 1;

void signal_handler(int) {
    g_running = 0;
}

int main(int argc, char **argv) {
    const std::string device = (argc > 1) ? argv[1] : "/dev/video0";
    const int width  = 1920;
    const int height = 1080;

    std::signal(SIGINT, signal_handler);

    // Build a GStreamer pipeline that:
    // - grabs from /dev/video0 using v4l2src
    // - negotiates BGR frames at the desired resolution
    // - converts as needed
    // - delivers BGR frames to OpenCV via appsink
    std::ostringstream pipeline;
    pipeline
        << "v4l2src device=" << device << " io-mode=2 ! "
        << "video/x-raw,format=BGR,width=" << width << ",height=" << height << " ! "
        << "videoconvert ! "
        << "video/x-raw,format=BGR ! "
        << "appsink";

    std::cout << "Using pipeline: " << pipeline.str() << std::endl;

    cv::VideoCapture cap(pipeline.str(), cv::CAP_GSTREAMER);
    if (!cap.isOpened()) {
        std::cerr << "Failed to open pipeline for device " << device << std::endl;
        return 1;
    }

    int w = static_cast<int>(cap.get(cv::CAP_PROP_FRAME_WIDTH));
    int h = static_cast<int>(cap.get(cv::CAP_PROP_FRAME_HEIGHT));
    std::cout << "Stream opened at " << w << "x" << h << std::endl;

    cv::namedWindow("TPG", cv::WINDOW_NORMAL);

    cv::Mat frame;
    while (g_running) {
        if (!cap.read(frame) || frame.empty()) {
            std::cerr << "Read failed" << std::endl;
            break;
        }

        cv::imshow("TPG", frame);
        int key = cv::waitKey(1) & 0xff;
        if (key == 'q' || key == 27) {
            break;
        }
    }

    cv::destroyAllWindows();
    cap.release();
    return 0;
}
