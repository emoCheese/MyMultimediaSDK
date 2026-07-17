# MultimediaSDK

Cross-platform multimedia SDK providing RTSP streaming, H.264 decoding, and MP4 recording based on GStreamer + FFmpeg.

## Features

- RTSP pull (TCP/UDP) via GStreamer rtspsrc
- H.264 decode (CPU: avdec_h264, GPU: D3D11VA / VAAPI / NVDEC)
- MP4 lossless recording (remux, no re-encoding)
- Hardware decode auto-detection at runtime
- Self-contained build from source (no system GStreamer/FFmpeg required)

## Supported Platforms

| Platform | Minimum OS | Compiler |
|----------|-----------|----------|
| Linux x64 | Ubuntu 20.04+ | GCC 9.4+ |
| Linux ARM64 | Ubuntu 20.04+ | aarch64-linux-gnu |
| Windows x64 | Windows 10 / Server 2019+ | MSVC 2019+ |

## Quick Start

### Build from source

```bash
git clone --recurse-submodules https://github.com/example/MultimediaSDK.git
cd MultimediaSDK

# Build (auto-detect platform)
python3 build.py

# Or specify target explicitly
python3 build.py --target linux-x64 --package
```

### Using the SDK

```cmake
find_package(MultimediaSDK REQUIRED)

add_executable(my_app main.c)
target_link_libraries(my_app
    MultimediaSDK::gstreamer
    MultimediaSDK::gstvideo
    MultimediaSDK::gstapp
)
```

```c
#include <gst/gst.h>

int main(int argc, char *argv[]) {
    gst_init(&argc, &argv);
    GstElement *pipeline = gst_parse_launch(
        "rtspsrc location=rtsp://... ! rtph264depay ! h264parse ! "
        "avdec_h264 ! mp4mux ! filesink location=output.mp4",
        NULL
    );
    gst_element_set_state(pipeline, GST_STATE_PLAYING);
    g_main_loop_run(g_main_loop_new(NULL, FALSE));
    return 0;
}
```

## SDK Layout

```
MultimediaSDK-1.0.0-linux-x64/
├── include/    # GStreamer, GLib, FFmpeg headers
├── lib/        # Static libraries (.a)
├── plugins/    # GStreamer dynamic plugins (.so/.dll)
└── cmake/      # CMake config (find_package)
```

## Customization

Edit `config/modules.ini` to enable/disable modules:

```ini
[plugins.bad]
d3d11 = false      # Disable D3D11VA
va = false         # Disable VAAPI
nvcodec = false    # Disable NVDEC

[ffmpeg]
decoders = h264    # CPU-only H.264 decode
```

Then rebuild: `python3 build.py --clean`

## License

GStreamer and FFmpeg components are under their respective licenses (LGPL/GPL).
