// ghostty_stub.c — No-op stub implementations for development builds.
//
// These allow the project to compile and run without the real GhosttyKit
// xcframework. Every function returns a failure/null value so that
// CLIGhosttyTerminalRunner.isAvailable evaluates to false at runtime.

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"

#include "ghostty.h"
#include <stdlib.h>

// Config
ghostty_config_t ghostty_config_new(void) { return NULL; }
void ghostty_config_free(ghostty_config_t config) { (void)config; }
bool ghostty_config_load_default(ghostty_config_t config) { (void)config; return false; }
bool ghostty_config_set(ghostty_config_t config, const char *key, const char *value) {
    (void)config; (void)key; (void)value; return false;
}

// App
ghostty_app_t ghostty_app_new(ghostty_config_t config) { (void)config; return NULL; }
void ghostty_app_free(ghostty_app_t app) { (void)app; }
bool ghostty_app_tick(ghostty_app_t app) { (void)app; return false; }

// Surface
ghostty_surface_t ghostty_surface_new(ghostty_app_t app,
                                      ghostty_surface_config_s config,
                                      ghostty_runtime_s runtime) {
    (void)app; (void)config; (void)runtime;
    return NULL;
}
void ghostty_surface_free(ghostty_surface_t surface) { (void)surface; }
void ghostty_surface_key(ghostty_surface_t surface, ghostty_input_key_s input) {
    (void)surface; (void)input;
}
void ghostty_surface_text(ghostty_surface_t surface, const char *text) {
    (void)surface; (void)text;
}
void ghostty_surface_mouse(ghostty_surface_t surface, ghostty_input_mouse_s input) {
    (void)surface; (void)input;
}
void ghostty_surface_set_size(ghostty_surface_t surface, ghostty_surface_size_s size) {
    (void)surface; (void)size;
}
void ghostty_surface_set_content_scale(ghostty_surface_t surface,
                                       double scale_x, double scale_y) {
    (void)surface; (void)scale_x; (void)scale_y;
}
void ghostty_surface_set_focus(ghostty_surface_t surface, bool focused) {
    (void)surface; (void)focused;
}
const char *ghostty_surface_working_directory(ghostty_surface_t surface) {
    (void)surface; return NULL;
}
void ghostty_surface_close(ghostty_surface_t surface) { (void)surface; }

// Utility
const char *ghostty_version(void) { return NULL; }
bool ghostty_is_available(void) { return false; }

#pragma clang diagnostic pop
