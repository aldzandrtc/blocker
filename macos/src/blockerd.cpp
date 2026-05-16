#include "app_blocker.h"
#include "settings_store.h"
#include <cstdio>
#include <cstring>
#include <csignal>
#include <CoreFoundation/CoreFoundation.h>

static AppBlocker* g_blocker = nullptr;

static void handle_signal(int sig) {
    fprintf(stderr, "blockerd: received signal %d, shutting down\n", sig);
    if (g_blocker) g_blocker->stop();
    exit(0);
}

int main(int argc, char** argv) {
    bool foreground = false;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--foreground") == 0 || strcmp(argv[i], "-f") == 0) {
            foreground = true;
        } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            printf("blockerd — AI-powered app blocker daemon\n");
            printf("Usage: blockerd [--foreground]\n");
            printf("  --foreground, -f    Run in foreground (don't daemonize)\n");
            return 0;
        }
    }

    if (!foreground) {
        // Daemonize
        pid_t pid = fork();
        if (pid < 0) return 1;
        if (pid > 0) {
            printf("blockerd started (pid %d)\n", pid);
            return 0;
        }
        // Child: detach from terminal
        setsid();
        fclose(stdin);
        fclose(stdout);
    }

    signal(SIGTERM, handle_signal);
    signal(SIGINT, handle_signal);

    fprintf(stderr, "blockerd: starting (pid %d)\n", getpid());

    SettingsStore settings;
    if (!settings.has_api_key()) {
        fprintf(stderr, "blockerd: no API key configured. Run 'blocker setup'.\n");
        return 1;
    }

    AppBlocker blocker(&settings);
    g_blocker = &blocker;

    if (blocker.start() != 0) {
        fprintf(stderr, "blockerd: failed to start\n");
        return 1;
    }

    // Run the main event loop (required for NSWorkspace notifications)
    CFRunLoopRun();

    return 0;
}
