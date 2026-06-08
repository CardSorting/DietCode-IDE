#import "MacWindow+Private.hpp"
#import "MacWindowUtilities.hpp"
#import "MacEditorComponents.hpp"
#import "MacControlSupport.hpp"

#include <util.h>
#include <unistd.h>
#include <termios.h>
#include <crt_externs.h>

using namespace dietcode::platform::macos;

@implementation DietCodeWindowController (RunTerminal)

- (void)setupRunUI {
    NSStackView* runStack = [[NSStackView alloc] init];
    [runStack setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [runStack setSpacing:16];
    [runStack setEdgeInsets:NSEdgeInsetsMake(12, 12, 12, 12)];
    [runStack setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.runSidebarView addSubview:runStack];

    [NSLayoutConstraint activateConstraints:@[
        [runStack.leadingAnchor constraintEqualToAnchor:self.runSidebarView.leadingAnchor],
        [runStack.trailingAnchor constraintEqualToAnchor:self.runSidebarView.trailingAnchor],
        [runStack.topAnchor constraintEqualToAnchor:self.runSidebarView.topAnchor]
    ]];

    [runStack addArrangedSubview:MakeLabel(@"RUN PROGRAM", 13, NSFontWeightBold)];
    
    NSButton* runBtn = [NSButton buttonWithTitle:@"Run File" target:self action:@selector(runCurrentFile:)];
    [runBtn setBezelStyle:NSBezelStyleRounded];
    [runBtn setControlSize:NSControlSizeLarge];
    
    NSButton* stopBtn = [NSButton buttonWithTitle:@"Stop File" target:self action:@selector(stopCurrentFile:)];
    [stopBtn setBezelStyle:NSBezelStyleRounded];
    [stopBtn setControlSize:NSControlSizeLarge];
    [stopBtn setEnabled:NO];
    
    [runStack addArrangedSubview:runBtn];
    [runStack addArrangedSubview:stopBtn];
    
    self.runStatusLabel = MakeLabel(@"Ready to run", 13, NSFontWeightRegular);
    [self.runStatusLabel setTextColor:[NSColor secondaryLabelColor]];
    self.runExplanationLabel = MakeLabel(@"", 12, NSFontWeightRegular);
    [self.runExplanationLabel setTextColor:[NSColor systemOrangeColor]];
    
    [runStack addArrangedSubview:self.runStatusLabel];
    [runStack addArrangedSubview:self.runExplanationLabel];
}

- (void)runCurrentFile:(id)sender {
    if (self.activeTab == nil) return;
    
    [self saveTab:self.activeTab];
    if (self.activeTab.path == nil) return;
    
    NSString* filePath = self.activeTab.path;
    NSString* ext = [[filePath pathExtension] lowercaseString];
    
    [self.outputTextView setString:@""];
    [self.errorsTextView setString:@""];
    [self updatePlaceholderVisibility:self.outputTextView];
    [self updatePlaceholderVisibility:self.errorsTextView];
    
    [self showBottomPanelTab:@"output"];
    [self.bottomPanel setHidden:NO];
    [self.runStatusLabel setStringValue:@"Running..."];
    [self.runExplanationLabel setStringValue:@""];
    
    for (NSView* v in [self.runSidebarView.subviews[0] arrangedSubviews]) {
        if ([v isKindOfClass:[NSButton class]]) {
            NSButton* b = (NSButton*)v;
            if ([b.title isEqualToString:@"Run File"]) [b setEnabled:NO];
            if ([b.title isEqualToString:@"Stop File"]) [b setEnabled:YES];
        }
    }
    
    NSString* command = nil;
    NSArray* args = nil;
    
    if ([ext isEqualToString:@"py"]) {
        command = @"/usr/bin/python3";
        args = @[filePath];
    } else if ([ext isEqualToString:@"js"]) {
        command = @"/usr/bin/env";
        args = @[@"node", filePath];
    } else if ([ext isEqualToString:@"cpp"] || [ext isEqualToString:@"cc"]) {
        [self runCPPCompilation:filePath];
        return;
    } else {
        command = @"/bin/zsh";
        args = @[filePath];
    }
    
    [self executeTask:command arguments:args];
}

- (void)stopCurrentFile:(id)sender {
    if (self.currentRunTask && [self.currentRunTask isRunning]) {
        [self.currentRunTask terminate];
        [self updateRunStatus:@"Stopped" success:NO];
    }
}

- (void)runCPPCompilation:(NSString*)filePath {
    [self.runStatusLabel setStringValue:@"Compiling C++..."];
    
    NSString* outPath = @"/tmp/dietcode_cpp_run";
    NSTask* compileTask = [[NSTask alloc] init];
    [compileTask setLaunchPath:@"/usr/bin/clang++"];
    [compileTask setArguments:@[@"-std=c++20", @"-Wall", @"-Wextra", filePath, @"-o", outPath]];
    
    NSPipe* errPipe = [NSPipe pipe];
    [compileTask setStandardError:errPipe];
    [compileTask setStandardOutput:errPipe];
    
    __weak DietCodeWindowController* weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        DietCodeWindowController* strongSelf = weakSelf;
        if (!strongSelf) return;
        @try {
            [compileTask launch];
            NSData* errData = [[errPipe fileHandleForReading] readDataToEndOfFile];
            [compileTask waitUntilExit];
            NSString* errText = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf appendOutputText:errText];
                
                [strongSelf problemsClearSource:@"compiler"];
                NSArray* parsedDiags = [strongSelf parseCompilerOutput:errText];
                [strongSelf handleDiagnostics:parsedDiags forFile:filePath source:@"compiler"];
                
                if (compileTask.terminationStatus == 0) {
                    [strongSelf executeTask:outPath arguments:@[]];
                } else {
                    [strongSelf updateRunStatus:@"Compilation Failed" success:NO];
                    [strongSelf showBottomPanelTab:@"errors"];
                }
            });
        } @catch (NSException* exception) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf updateRunStatus:@"Compiler not found" success:NO];
            });
        }
    });
}

- (void)executeTask:(NSString*)launchPath arguments:(NSArray*)args {
    if (self.currentRunTask && [self.currentRunTask isRunning]) {
        [self.currentRunTask terminate];
    }
    
    self.currentRunTask = [[NSTask alloc] init];
    [self.currentRunTask setLaunchPath:launchPath];
    [self.currentRunTask setArguments:args];
    [self.currentRunTask setCurrentDirectoryPath:self.openedFolderPath ?: [NSHomeDirectory() stringByDeletingLastPathComponent]];
    
    NSPipe* pipe = [NSPipe pipe];
    [self.currentRunTask setStandardOutput:pipe];
    [self.currentRunTask setStandardError:pipe];
    
    NSFileHandle* file = [pipe fileHandleForReading];
    __weak DietCodeWindowController* weakSelf = self;
    
    @try {
        [self.currentRunTask launch];
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            while (true) {
                NSData* data = [file availableData];
                if (data.length == 0) break;
                NSString* text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                dispatch_async(dispatch_get_main_queue(), ^{
                    DietCodeWindowController* strongSelf = weakSelf;
                    if (strongSelf) [strongSelf appendOutputText:text];
                });
            }
            DietCodeWindowController* strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf.currentRunTask waitUntilExit];
                int status = strongSelf.currentRunTask.terminationStatus;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [strongSelf updateRunStatus:[NSString stringWithFormat:@"Finished (Exit Code %d)", status] success:(status == 0)];
                });
            }
        });
    } @catch (NSException* e) {
        [self appendOutputText:[NSString stringWithFormat:@"Failed to run file: %@\n", e.reason]];
        [self updateRunStatus:@"Runtime not found" success:NO];
    }
}

- (void)updateRunStatus:(NSString*)status success:(BOOL)ok {
    self.runStatusLabel.stringValue = status;
    self.runStatusLabel.textColor = ok ? [NSColor systemGreenColor] : [NSColor systemRedColor];
    
    for (NSView* v in [self.runSidebarView.subviews[0] arrangedSubviews]) {
        if ([v isKindOfClass:[NSButton class]]) {
            NSButton* b = (NSButton*)v;
            if ([b.title isEqualToString:@"Run File"]) [b setEnabled:YES];
            if ([b.title isEqualToString:@"Stop File"]) [b setEnabled:NO];
        }
    }
}

- (void)appendOutputText:(NSString*)text {
    NSTextStorage* storage = self.outputTextView.textStorage;
    [storage beginEditing];
    [storage appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{
        NSForegroundColorAttributeName: [NSColor textColor],
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]
    }]];
    [storage endEditing];
    [self.outputTextView scrollRangeToVisible:NSMakeRange(storage.length, 0)];
    [self updatePlaceholderVisibility:self.outputTextView];
}

- (void)setupTerminalProcess {
    struct termios ios;
    memset(&ios, 0, sizeof(ios));
    cfmakeraw(&ios);
    ios.c_cflag |= CS8;
    
    int masterFd = -1;
    pid_t pid = forkpty(&masterFd, NULL, &ios, NULL);
    if (pid < 0) {
        [self appendTerminalText:@"Could not launch local pseudo-terminal pty.\n"];
        return;
    }
    
    if (pid == 0) {
        setenv("TERM", "xterm-256color", 1);
        char* argv[] = { (char*)"/bin/zsh", (char*)"-l", NULL };
        char** env = *_NSGetEnviron();
        execve(argv[0], argv, env);
        char* argvSh[] = { (char*)"/bin/sh", NULL };
        execve(argvSh[0], argvSh, env);
        exit(1);
    }
    
    terminalMasterFd_ = masterFd;
    terminalPid_ = pid;
    self.terminalTextView.masterFd = masterFd;
    
    __weak DietCodeWindowController* weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        char buf[1024];
        while (true) {
            ssize_t bytes = read(masterFd, buf, sizeof(buf) - 1);
            if (bytes <= 0) break;
            buf[bytes] = '\0';
            NSString* text = [NSString stringWithUTF8String:buf] ?: [[NSString alloc] initWithBytes:buf length:bytes encoding:NSASCIIStringEncoding];
            dispatch_async(dispatch_get_main_queue(), ^{
                DietCodeWindowController* strongSelf = weakSelf;
                if (strongSelf) [strongSelf appendTerminalText:text];
            });
        }
    });
}

- (void)appendTerminalText:(NSString*)text {
    NSTextStorage* storage = self.terminalTextView.textStorage;
    [storage beginEditing];
    [storage appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{
        NSForegroundColorAttributeName: [self isDarkTheme] ? [NSColor whiteColor] : [NSColor blackColor],
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]
    }]];
    [storage endEditing];
    [self.terminalTextView scrollRangeToVisible:NSMakeRange(storage.length, 0)];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kDietCodeTerminalOutputDidUpdateNotification
                                                        object:self
                                                      userInfo:@{ @"text": text }];
}

- (void)ensureTerminalProcess {
    if (terminalPid_ <= 0) {
        [self setupTerminalProcess];
    }
}

@end
