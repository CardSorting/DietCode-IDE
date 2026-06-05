#include "MacAppDelegate.hpp"

#import <Cocoa/Cocoa.h>
#include <signal.h>
#include <unistd.h>

void handle_termination_signal(int sig) {
    (void)sig;
    NSString* dcDir = [NSHomeDirectory() stringByAppendingPathComponent:@".dietcode"];
    unlink([[dcDir stringByAppendingPathComponent:@"control.sock"] UTF8String]);
    unlink([[dcDir stringByAppendingPathComponent:@"session.token"] UTF8String]);
    _exit(0);
}

int main(int argc, const char * argv[]) {
  @autoreleasepool {
    signal(SIGINT, handle_termination_signal);
    signal(SIGTERM, handle_termination_signal);

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


