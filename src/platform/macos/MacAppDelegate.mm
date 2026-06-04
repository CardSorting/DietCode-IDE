#include "MacAppDelegate.hpp"
#include "MacMenu.hpp"
#include "MacWindow.hpp"

#import <Cocoa/Cocoa.h>

@interface DietCodeAppDelegate ()
@property(nonatomic, copy) NSString* pendingFileToOpen;
@end

@implementation DietCodeAppDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        self.windowController = [[DietCodeWindowController alloc] init];
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    [DietCodeMenuBuilder installMainMenuWithTarget:self.windowController];
    [self.windowController showWindow:self];
    [NSApp activateIgnoringOtherApps:YES];
    
    if (self.pendingFileToOpen) {
        [self.windowController openFileAtPath:self.pendingFileToOpen line:1 column:1];
        self.pendingFileToOpen = nil;
    }
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    if (self.windowController) {
        if ([[self.windowController window] isVisible]) {
            [self.windowController openFileAtPath:filename line:1 column:1];
        } else {
            self.pendingFileToOpen = filename;
        }
        return YES;
    }
    return NO;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
    return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender {
    if (self.windowController != nil && ![self.windowController confirmCloseIfNeeded]) {
        return NSTerminateCancel;
    }
    if (self.windowController != nil) {
        [self.windowController cleanupProcesses];
    }
    return NSTerminateNow;
}

@end
