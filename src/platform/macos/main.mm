#include "MacAppDelegate.hpp"

#import <Cocoa/Cocoa.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static char g_sockPath[1024] = {0};
static char g_tokenPath[1024] = {0};

void handle_termination_signal(int sig) {
    (void)sig;
    if (g_sockPath[0] != '\0') {
        unlink(g_sockPath);
    }
    if (g_tokenPath[0] != '\0') {
        unlink(g_tokenPath);
    }
    _exit(0);
}

static bool connect_control_socket(const char* sockPath) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        return false;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    if (strlen(sockPath) >= sizeof(addr.sun_path)) {
        close(fd);
        return false;
    }
    strncpy(addr.sun_path, sockPath, sizeof(addr.sun_path) - 1);

    bool ok = (connect(fd, (struct sockaddr*)&addr, sizeof(addr)) == 0);
    close(fd);
    return ok;
}

static void detach_standard_fds(void) {
    int devNull = open("/dev/null", O_RDWR);
    if (devNull < 0) {
        return;
    }
    dup2(devNull, STDIN_FILENO);
    dup2(devNull, STDOUT_FILENO);
    dup2(devNull, STDERR_FILENO);
    if (devNull > STDERR_FILENO) {
        close(devNull);
    }
}

static int ensure_control_socket(const char* executablePath, const char* sockPath, double timeoutSeconds) {
    if (connect_control_socket(sockPath)) {
        printf("DietCode control socket is active at %s\n", sockPath);
        return 0;
    }

    pid_t pid = fork();
    if (pid < 0) {
        fprintf(stderr, "Failed to fork DietCode headless process: %s\n", strerror(errno));
        return 1;
    }

    if (pid == 0) {
        setsid();
        detach_standard_fds();
        char* childArgv[] = {
            const_cast<char*>(executablePath),
            const_cast<char*>("--headless"),
            nullptr
        };
        execvp(executablePath, childArgv);
        _exit(127);
    }

    int attempts = (int)(timeoutSeconds * 10.0);
    if (attempts < 1) {
        attempts = 1;
    }
    for (int i = 0; i < attempts; ++i) {
        usleep(100000);
        if (connect_control_socket(sockPath)) {
            printf("DietCode control socket started at %s\n", sockPath);
            return 0;
        }
    }

    fprintf(stderr, "Timed out waiting for DietCode control socket at %s\n", sockPath);
    return 1;
}

int main(int argc, const char * argv[]) {
  @autoreleasepool {
    NSString* homeDir = NSHomeDirectory();
    NSString* dcDir = [homeDir stringByAppendingPathComponent:@".dietcode"];
    NSString* sockPathStr = [dcDir stringByAppendingPathComponent:@"control.sock"];
    NSString* tokenPathStr = [dcDir stringByAppendingPathComponent:@"session.token"];
    
    [sockPathStr getFileSystemRepresentation:g_sockPath maxLength:sizeof(g_sockPath)];
    [tokenPathStr getFileSystemRepresentation:g_tokenPath maxLength:sizeof(g_tokenPath)];

    BOOL headless = NO;
    BOOL ensureSocket = NO;
    double ensureTimeoutSeconds = 10.0;
    for (int i = 1; i < argc; ++i) {
      if (strcmp(argv[i], "--headless") == 0) {
        headless = YES;
      } else if (strcmp(argv[i], "--ensure-socket") == 0 || strcmp(argv[i], "--ensure-control-socket") == 0) {
        ensureSocket = YES;
      } else if (strcmp(argv[i], "--ensure-timeout") == 0 && i + 1 < argc) {
        ensureTimeoutSeconds = atof(argv[++i]);
      }
    }

    if (ensureSocket) {
      return ensure_control_socket(argv[0], g_sockPath, ensureTimeoutSeconds);
    }

    signal(SIGINT, handle_termination_signal);
    signal(SIGTERM, handle_termination_signal);
    signal(SIGQUIT, handle_termination_signal);
    signal(SIGHUP, handle_termination_signal);

    NSApplication *app = [NSApplication sharedApplication];
    if (headless) {
      [app setActivationPolicy:NSApplicationActivationPolicyProhibited];
    } else {
      [app setActivationPolicy:NSApplicationActivationPolicyRegular];
    }

    DietCodeAppDelegate *delegate = [[DietCodeAppDelegate alloc] init];
    delegate.isHeadless = headless;
    [app setDelegate:delegate];
    [app run];
  }

  return 0;
}
