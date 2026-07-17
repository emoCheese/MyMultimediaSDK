#include <gst/gst.h>
#include <stdio.h>

int main(int argc, char *argv[]) {
    gst_init(&argc, &argv);

    printf("GStreamer version: %d.%d.%d\n",
           GST_VERSION_MAJOR, GST_VERSION_MINOR, GST_VERSION_MICRO);

    const char *elements[] = {
        "rtspsrc",
        "rtph264depay",
        "h264parse",
        "avdec_h264",
        "mp4mux",
        "filesink",
        "fakesink",
        NULL
    };

    int failures = 0;
    for (int i = 0; elements[i]; i++) {
        GstElementFactory *factory = gst_element_factory_find(elements[i]);
        if (factory) {
            printf("  [OK]    %s\n", elements[i]);
            gst_object_unref(factory);
        } else {
            printf("  [MISS]  %s\n", elements[i]);
            failures++;
        }
    }

    GError *error = NULL;
    GstElement *pipeline = gst_parse_launch(
        "videotestsrc num-buffers=1 ! fakesink", &error);
    if (pipeline && !error) {
        printf("  [OK]    Pipeline created successfully\n");
        gst_object_unref(pipeline);
    } else {
        printf("  [WARN]  Pipeline creation failed: %s\n",
               error ? error->message : "unknown");
        if (error) g_error_free(error);
    }

    gst_deinit();

    if (failures > 0) {
        printf("\nFAIL: %d elements missing\n", failures);
        return 1;
    }
    printf("\nAll %d elements available.\n", 7);
    return 0;
}
