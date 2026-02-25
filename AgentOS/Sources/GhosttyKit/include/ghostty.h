// ghostty.h — Development stub for GhosttyKit C API
//
// This header defines the types and function signatures from libghostty's
// embedded apprt. In development mode, stub implementations (ghostty_stub.c)
// are linked so the project compiles without the real GhosttyKit.xcframework.
//
// To switch to the real library:
//   1. Run: bash scripts/build-ghosttykit.sh
//   2. In Package.swift, swap the GhosttyKit target (see comments there).

#ifndef GHOSTTY_H
#define GHOSTTY_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#pragma clang assume_nonnull begin

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Opaque types
// ---------------------------------------------------------------------------

typedef struct ghostty_app_s *ghostty_app_t;
typedef struct ghostty_surface_s *ghostty_surface_t;
typedef struct ghostty_config_s *ghostty_config_t;

// ---------------------------------------------------------------------------
// Surface size (in pixels)
// ---------------------------------------------------------------------------

typedef struct {
    uint32_t width;
    uint32_t height;
} ghostty_surface_size_s;

// ---------------------------------------------------------------------------
// Key / mouse input
// ---------------------------------------------------------------------------

typedef enum {
    GHOSTTY_MODS_NONE  = 0,
    GHOSTTY_MODS_SHIFT = 1 << 0,
    GHOSTTY_MODS_CTRL  = 1 << 1,
    GHOSTTY_MODS_ALT   = 1 << 2,
    GHOSTTY_MODS_SUPER = 1 << 3,
} ghostty_input_mods_e;

typedef struct {
    uint32_t keycode;
    uint32_t modifiers;
    const char * _Nullable text;
    bool is_repeat;
} ghostty_input_key_s;

typedef enum {
    GHOSTTY_MOUSE_PRESS   = 0,
    GHOSTTY_MOUSE_RELEASE = 1,
    GHOSTTY_MOUSE_MOVE    = 2,
    GHOSTTY_MOUSE_SCROLL  = 3,
} ghostty_mouse_action_e;

typedef enum {
    GHOSTTY_MOUSE_LEFT   = 0,
    GHOSTTY_MOUSE_RIGHT  = 1,
    GHOSTTY_MOUSE_MIDDLE = 2,
} ghostty_mouse_button_e;

typedef struct {
    ghostty_mouse_action_e action;
    ghostty_mouse_button_e button;
    uint32_t modifiers;
    double x;
    double y;
    double scroll_x;
    double scroll_y;
} ghostty_input_mouse_s;

// ---------------------------------------------------------------------------
// Runtime callbacks
// ---------------------------------------------------------------------------

typedef void (*ghostty_runtime_set_title_fn)(void *userdata, const char *title);
typedef void (*ghostty_runtime_set_cwd_fn)(void *userdata, const char *path);
typedef void (*ghostty_runtime_exit_fn)(void *userdata, int32_t exit_code);
typedef void (*ghostty_runtime_needs_display_fn)(void *userdata);
typedef void (*ghostty_runtime_output_fn)(void *userdata, const uint8_t *data,
                                          size_t length);

typedef struct {
    void * _Nullable userdata;
    ghostty_runtime_set_title_fn set_title;
    ghostty_runtime_set_cwd_fn set_cwd;
    ghostty_runtime_exit_fn on_exit;
    ghostty_runtime_needs_display_fn needs_display;
    ghostty_runtime_output_fn on_output;
} ghostty_runtime_s;

// ---------------------------------------------------------------------------
// Surface configuration
// ---------------------------------------------------------------------------

typedef struct {
    const char * _Nullable command;
    const char * _Nullable working_directory;
    const char * _Nullable const * _Nullable env_keys;
    const char * _Nullable const * _Nullable env_values;
    uint32_t env_count;
    void * _Nullable metal_layer;
} ghostty_surface_config_s;

// ---------------------------------------------------------------------------
// Config API
// ---------------------------------------------------------------------------

ghostty_config_t _Nullable ghostty_config_new(void);
void ghostty_config_free(ghostty_config_t config);
bool ghostty_config_load_default(ghostty_config_t config);
bool ghostty_config_set(ghostty_config_t config, const char *key,
                        const char *value);

// ---------------------------------------------------------------------------
// App API
// ---------------------------------------------------------------------------

ghostty_app_t _Nullable ghostty_app_new(ghostty_config_t config);
void ghostty_app_free(ghostty_app_t app);
bool ghostty_app_tick(ghostty_app_t app);

// ---------------------------------------------------------------------------
// Surface API
// ---------------------------------------------------------------------------

ghostty_surface_t _Nullable ghostty_surface_new(ghostty_app_t app,
                                                ghostty_surface_config_s config,
                                                ghostty_runtime_s runtime);
void ghostty_surface_free(ghostty_surface_t surface);
void ghostty_surface_key(ghostty_surface_t surface, ghostty_input_key_s input);
void ghostty_surface_text(ghostty_surface_t surface, const char *text);
void ghostty_surface_mouse(ghostty_surface_t surface,
                           ghostty_input_mouse_s input);
void ghostty_surface_set_size(ghostty_surface_t surface,
                              ghostty_surface_size_s size);
void ghostty_surface_set_content_scale(ghostty_surface_t surface,
                                       double scale_x, double scale_y);
void ghostty_surface_set_focus(ghostty_surface_t surface, bool focused);
const char * _Nullable ghostty_surface_working_directory(
    ghostty_surface_t surface);
void ghostty_surface_close(ghostty_surface_t surface);

// ---------------------------------------------------------------------------
// Utility
// ---------------------------------------------------------------------------

const char * _Nullable ghostty_version(void);
bool ghostty_is_available(void);

#ifdef __cplusplus
}
#endif

#pragma clang assume_nonnull end

#endif // GHOSTTY_H
