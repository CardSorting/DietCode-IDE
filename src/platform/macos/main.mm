#include "MacAppDelegate.hpp"

#import <Cocoa/Cocoa.h>
#include <signal.h>
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

int main(int argc, const char * argv[]) {
  @autoreleasepool {
    NSString* homeDir = NSHomeDirectory();
    NSString* dcDir = [homeDir stringByAppendingPathComponent:@".dietcode"];
    NSString* sockPathStr = [dcDir stringByAppendingPathComponent:@"control.sock"];
    NSString* tokenPathStr = [dcDir stringByAppendingPathComponent:@"session.token"];
    
    [sockPathStr getFileSystemRepresentation:g_sockPath maxLength:sizeof(g_sockPath)];
    [tokenPathStr getFileSystemRepresentation:g_tokenPath maxLength:sizeof(g_tokenPath)];

    signal(SIGINT, handle_termination_signal);
    signal(SIGTERM, handle_termination_signal);
    signal(SIGQUIT, handle_termination_signal);
    signal(SIGHUP, handle_termination_signal);

    BOOL headless = NO;
    for (int i = 1; i < argc; ++i) {
      if (strcmp(argv[i], "--headless") == 0) {
        headless = YES;
        break;
      }
    }

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


