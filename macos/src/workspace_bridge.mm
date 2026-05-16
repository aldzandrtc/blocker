#import <Cocoa/Cocoa.h>
#import <signal.h>
#include "workspace_bridge.h"
#include <cstring>
#include <string>
#include <vector>
#include <dispatch/dispatch.h>

struct WorkspaceBridge {
    AppLaunchCallback callback;
    void* context;
    id observer;
};

WorkspaceBridge* bridge_create(void) {
    auto* b = new WorkspaceBridge();
    b->callback = nullptr;
    b->context = nullptr;
    b->observer = nil;
    return b;
}

void bridge_destroy(WorkspaceBridge* b) {
    bridge_stop_monitoring(b);
    delete b;
}

int bridge_start_monitoring(WorkspaceBridge* b,
                             AppLaunchCallback callback,
                             void* context) {
    b->callback = callback;
    b->context = context;

    auto nc = [[NSWorkspace sharedWorkspace] notificationCenter];
    b->observer = [nc addObserverForName:NSWorkspaceDidLaunchApplicationNotification
                                   object:nil
                                    queue:[NSOperationQueue mainQueue]
                               usingBlock:^(NSNotification* note) {
        if (!b->callback) return;
        NSRunningApplication* app =
            note.userInfo[NSWorkspaceApplicationKey];
        if (!app) return;

        AppInfo info;
        info.pid = app.processIdentifier;
        info.bundle_id = app.bundleIdentifier
            ? [app.bundleIdentifier UTF8String] : "";
        info.display_name = app.localizedName
            ? [app.localizedName UTF8String] : "";

        b->callback(&info, b->context);
    }];

    return b->observer ? 0 : -1;
}

void bridge_stop_monitoring(WorkspaceBridge* b) {
    if (b->observer) {
        [[[NSWorkspace sharedWorkspace] notificationCenter]
            removeObserver:b->observer];
        b->observer = nil;
    }
}

void bridge_suspend_app(int pid) { kill(pid, SIGSTOP); }
void bridge_resume_app(int pid) { kill(pid, SIGCONT); }
void bridge_kill_app(int pid)   { kill(pid, SIGKILL); }

static char* str_alloc(const std::string& s) {
    char* out = (char*)malloc(s.size() + 1);
    if (out) { std::memcpy(out, s.c_str(), s.size() + 1); }
    return out;
}

char* bridge_show_judge_dialog(const char* app_name) {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"%@ is blocked",
        [NSString stringWithUTF8String:app_name]];
    alert.informativeText =
        @"This app is on your strict blocklist. "
        @"Convince the AI guardian to let you use it.\n\n"
        @"The AI is extremely strict — vague excuses will be rejected.";
    [alert addButtonWithTitle:@"Submit"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField* input = [[NSTextField alloc]
        initWithFrame:NSMakeRect(0, 0, 320, 80)];
    input.placeholderString = @"Why do you need this app right now?";
    [input.cell setWraps:YES];
    [input.cell setScrollable:YES];
    alert.accessoryView = input;

    [alert.window makeFirstResponder:input];

    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        return str_alloc([input.stringValue UTF8String] ?: "");
    }
    return nullptr;
}

char* bridge_show_problem_dialog(const char* problem_text, int timeout_seconds) {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Solve this problem to continue";
    [alert addButtonWithTitle:@"Submit"];
    [alert addButtonWithTitle:@"Give Up"];

    NSTextField* input = [[NSTextField alloc]
        initWithFrame:NSMakeRect(0, 0, 320, 28)];
    input.placeholderString = @"Your answer";
    alert.accessoryView = input;

    // Countdown timer
    __block int remaining = timeout_seconds;
    __block bool timed_out = false;
    NSTimer* timer = [NSTimer scheduledTimerWithTimeInterval:1.0
        repeats:YES block:^(NSTimer*) {
        remaining--;
        if (remaining <= 0) {
            timed_out = true;
            [NSApp abortModal];
        } else {
            alert.informativeText = [NSString stringWithFormat:
                @"%s\n\nYou have %d seconds to answer.",
                problem_text, remaining];
        }
    }];

    alert.informativeText = [NSString stringWithFormat:
        @"%s\n\nYou have %d seconds to answer.",
        problem_text, timeout_seconds];

    [alert.window makeFirstResponder:input];
    NSModalResponse response = [alert runModal];
    [timer invalidate];

    if (!timed_out && response == NSAlertFirstButtonReturn) {
        return str_alloc([input.stringValue UTF8String] ?: "");
    }
    return nullptr;
}

int bridge_get_running_apps(AppInfo** apps) {
    auto running = [[NSWorkspace sharedWorkspace] runningApplications];
    int count = (int)running.count;
    if (count == 0) return 0;

    *apps = (AppInfo*)malloc(count * sizeof(AppInfo));
    int idx = 0;
    for (NSRunningApplication* app in running) {
        if (!app.bundleIdentifier) continue;
        (*apps)[idx].pid = app.processIdentifier;
        (*apps)[idx].bundle_id = strdup([app.bundleIdentifier UTF8String]);
        (*apps)[idx].display_name = strdup(
            [app.localizedName UTF8String] ?: "");
        idx++;
    }
    return idx;
}

void bridge_free_app_list(AppInfo* apps, int count) {
    for (int i = 0; i < count; i++) {
        free((void*)apps[i].bundle_id);
        free((void*)apps[i].display_name);
    }
    free(apps);
}
