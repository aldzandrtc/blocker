#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handle to the bridge state.
typedef struct WorkspaceBridge WorkspaceBridge;

// App info passed to the launch callback.
typedef struct {
    int pid;
    const char* bundle_id;
    const char* display_name;
} AppInfo;

// Callback type: invoked when any app finishes launching.
typedef void (*AppLaunchCallback)(const AppInfo* app, void* context);

// Create/destroy the bridge. Only one instance at a time.
WorkspaceBridge* bridge_create(void);
void bridge_destroy(WorkspaceBridge* b);

// Start monitoring app launches. The callback is invoked on each launch.
// Returns 0 on success, -1 on failure.
int bridge_start_monitoring(WorkspaceBridge* b,
                             AppLaunchCallback callback,
                             void* context);

// Stop monitoring.
void bridge_stop_monitoring(WorkspaceBridge* b);

// Process control.
void bridge_suspend_app(int pid);
void bridge_resume_app(int pid);
void bridge_kill_app(int pid);

// Show the "convince the AI" dialog. Returns a malloc'd string (caller must
// free) or NULL if the user cancelled.
char* bridge_show_judge_dialog(const char* app_name);

// Show the math problem dialog with a countdown timer. Returns the user's
// answer as a malloc'd string (caller must free) or NULL if cancelled/timed out.
char* bridge_show_problem_dialog(const char* problem_text, int timeout_seconds);

// Get all currently running apps. Returns count, fills apps array.
// Caller must free each app's bundle_id and display_name, then free apps.
int bridge_get_running_apps(AppInfo** apps);

// Free an AppInfo array returned by bridge_get_running_apps.
void bridge_free_app_list(AppInfo* apps, int count);

#ifdef __cplusplus
}
#endif
