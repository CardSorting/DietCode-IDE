#import "MacAgentSidebar.hpp"

static NSString* const kAgentSpeakerYou = @"You";
static NSString* const kAgentSpeakerHermes = @"Hermes";

static NSString* DietCodeAgentChatPath(void) {
    NSString* bundled = [[NSBundle mainBundle].bundlePath
        stringByAppendingPathComponent:@"Contents/Resources/bin/dietcode-agent-chat"];
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:bundled]) {
        return bundled;
    }
    NSString* pyBundled = [[NSBundle mainBundle].bundlePath
        stringByAppendingPathComponent:@"Contents/Resources/bin/dietcode-agent-chat.py"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:pyBundled]) {
        return pyBundled;
    }
    return nil;
}

static NSString* DietCodeEnableAgentPath(void) {
    NSString* bundled = [[NSBundle mainBundle].bundlePath
        stringByAppendingPathComponent:@"Contents/Resources/bin/dietcode-enable-agent"];
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:bundled]) {
        return bundled;
    }
    return nil;
}

static NSColor* AgentSidebarBackgroundColor(void) {
    if (@available(macOS 10.14, *)) {
        NSAppearanceName appearance = [NSApp.effectiveAppearance
            bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        if ([appearance isEqualToString:NSAppearanceNameDarkAqua]) {
            return [NSColor colorWithCalibratedWhite:0.14 alpha:1.0];
        }
    }
    return [NSColor colorWithCalibratedWhite:0.97 alpha:1.0];
}

@implementation DietCodeAgentSidebarView {
    NSScrollView* _transcriptScroll;
    BOOL _runningCommand;
    BOOL _cancelRequested;
    BOOL _workspaceAuthorityMatch;
    NSTask* _activeTask;
    NSInteger _lastExitCode;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _lastExitCode = 0;
        _workspaceAuthorityMatch = YES;
        [self buildInterface];
        [self appendTranscriptWithSpeaker:kAgentSpeakerHermes
                                  message:@"Agent chat ready. Open a folder, then send a prompt."];
        [self refreshStatus];
    }
    return self;
}

- (void)buildInterface {
    [self setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self setWantsLayer:YES];
    self.layer.backgroundColor = AgentSidebarBackgroundColor().CGColor;

    NSTextField* title = [NSTextField labelWithString:@"Agent"];
    [title setFont:[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]];
    [title setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self addSubview:title];

    _statusLabel = [NSTextField labelWithString:@"Status: Checking…"];
    [_statusLabel setFont:[NSFont systemFontOfSize:11 weight:NSFontWeightRegular]];
    [_statusLabel setTextColor:[NSColor secondaryLabelColor]];
    [_statusLabel setLineBreakMode:NSLineBreakByWordWrapping];
    [_statusLabel setMaximumNumberOfLines:6];
    [_statusLabel setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self addSubview:_statusLabel];

    _transcriptScroll = [[NSScrollView alloc] init];
    [_transcriptScroll setHasVerticalScroller:YES];
    [_transcriptScroll setDrawsBackground:YES];
    [_transcriptScroll setBorderType:NSBezelBorder];
    [_transcriptScroll setTranslatesAutoresizingMaskIntoConstraints:NO];

    _transcriptView = [[NSTextView alloc] init];
    [_transcriptView setEditable:NO];
    [_transcriptView setSelectable:YES];
    [_transcriptView setRichText:NO];
    [_transcriptView setFont:[NSFont systemFontOfSize:12 weight:NSFontWeightRegular]];
    [_transcriptView setTextContainerInset:NSMakeSize(8, 8)];
    [_transcriptScroll setDocumentView:_transcriptView];
    [self addSubview:_transcriptScroll];

    _inputField = [[NSTextField alloc] init];
    [_inputField setPlaceholderString:@"Ask the agent…"];
    [_inputField setFont:[NSFont systemFontOfSize:12 weight:NSFontWeightRegular]];
    [_inputField setDelegate:self];
    [_inputField setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self addSubview:_inputField];

    _sendButton = [NSButton buttonWithTitle:@"Send" target:self action:@selector(sendPrompt:)];
    [_sendButton setBezelStyle:NSBezelStyleRounded];
    [_sendButton setKeyEquivalent:@"\r"];
    [_sendButton setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self addSubview:_sendButton];

    _stopButton = [NSButton buttonWithTitle:@"Stop" target:self action:@selector(stopPrompt:)];
    [_stopButton setBezelStyle:NSBezelStyleRounded];
    [_stopButton setEnabled:NO];
    [_stopButton setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self addSubview:_stopButton];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
        [title.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [title.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],

        [_statusLabel.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],

        [_transcriptScroll.topAnchor constraintEqualToAnchor:_statusLabel.bottomAnchor constant:10],
        [_transcriptScroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [_transcriptScroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],

        [_inputField.topAnchor constraintEqualToAnchor:_transcriptScroll.bottomAnchor constant:10],
        [_inputField.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [_inputField.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
        [_inputField.heightAnchor constraintEqualToConstant:24],

        [_stopButton.topAnchor constraintEqualToAnchor:_inputField.bottomAnchor constant:8],
        [_stopButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [_stopButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],
        [_stopButton.widthAnchor constraintGreaterThanOrEqualToConstant:64],

        [_sendButton.centerYAnchor constraintEqualToAnchor:_stopButton.centerYAnchor],
        [_sendButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
        [_sendButton.widthAnchor constraintGreaterThanOrEqualToConstant:72],

        [_transcriptScroll.bottomAnchor constraintEqualToAnchor:_inputField.topAnchor constant:-10],
    ]];
}

- (void)appendTranscriptWithSpeaker:(NSString*)speaker message:(NSString*)message {
    if (message.length == 0) {
        return;
    }
    NSString* block = [NSString stringWithFormat:@"%@: %@\n\n", speaker, message];
    NSTextStorage* storage = _transcriptView.textStorage;
    if (storage.length > 0) {
        [storage appendAttributedString:[[NSAttributedString alloc] initWithString:block]];
    } else {
        [_transcriptView setString:block];
    }
    [_transcriptView scrollRangeToVisible:NSMakeRange(_transcriptView.string.length, 0)];
}

- (NSString*)workspacePath {
    if ([self.delegate respondsToSelector:@selector(agentSidebarWorkspacePath)]) {
        return [self.delegate agentSidebarWorkspacePath] ?: @"";
    }
    return @"";
}

- (BOOL)updateWorkspaceAuthorityFromPayload:(NSDictionary*)payload requested:(NSString*)requested {
    NSDictionary* authority = payload[@"workspaceAuthority"];
    if (![authority isKindOfClass:[NSDictionary class]]) {
        authority = [payload valueForKeyPath:@"status.workspaceAuthority"];
    }
    if (![authority isKindOfClass:[NSDictionary class]]) {
        _workspaceAuthorityMatch = requested.length > 0;
        return _workspaceAuthorityMatch;
    }
    id matchValue = authority[@"workspaceMatch"];
    if (matchValue != nil) {
        _workspaceAuthorityMatch = [matchValue boolValue];
    } else {
        NSString* observed = authority[@"workspaceRootObserved"];
        _workspaceAuthorityMatch = requested.length == 0
            || (observed.length > 0 && [observed isEqualToString:requested]);
    }
    return _workspaceAuthorityMatch;
}

- (NSString*)statusTextFromDoctorJSON:(NSString*)output workspace:(NSString*)workspace exitCode:(NSInteger)exitCode running:(BOOL)running {
    NSMutableArray<NSString*>* lines = [NSMutableArray array];
    if (running) {
        [lines addObject:@"Running: Hermes active"];
    }
    if (workspace.length > 0) {
        [lines addObject:[NSString stringWithFormat:@"Workspace requested: %@", workspace]];
    } else {
        [lines addObject:@"Workspace requested: (none — open a folder)"];
    }
    [lines addObject:[NSString stringWithFormat:@"Last exit: %ld", (long)exitCode]];

    if (output.length == 0) {
        [lines insertObject:@"Runtime: unknown · Bridge: unknown · Hermes: unknown" atIndex:0];
        [lines insertObject:@"Workspace active: (unknown)" atIndex:1];
        return [lines componentsJoinedByString:@"\n"];
    }
    NSString* line = output;
    NSRange newline = [output rangeOfString:@"\n"];
    if (newline.location != NSNotFound) {
        line = [output substringToIndex:newline.location];
    }
    NSData* data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil) {
        [lines insertObject:@"Status: doctor output unreadable" atIndex:0];
        return [lines componentsJoinedByString:@"\n"];
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) {
        [lines insertObject:@"Status: doctor output not JSON" atIndex:0];
        return [lines componentsJoinedByString:@"\n"];
    }
    NSDictionary* payload = (NSDictionary*)json;
    [self updateWorkspaceAuthorityFromPayload:payload requested:workspace];

    NSDictionary* authority = payload[@"workspaceAuthority"];
    if (![authority isKindOfClass:[NSDictionary class]]) {
        authority = [payload valueForKeyPath:@"status.workspaceAuthority"];
    }
    NSString* observed = @"";
    if ([authority isKindOfClass:[NSDictionary class]]) {
        observed = authority[@"workspaceRootObserved"] ?: @"";
    }
    if (observed.length > 0) {
        [lines insertObject:[NSString stringWithFormat:@"Workspace active: %@", observed] atIndex:1];
    } else {
        [lines insertObject:@"Workspace active: (unknown)" atIndex:1];
    }
    if (workspace.length > 0 && !_workspaceAuthorityMatch) {
        [lines insertObject:@"Workspace mismatch — agent disabled" atIndex:2];
    }

    NSDictionary* status = payload[@"status"];
    if ([status isKindOfClass:[NSDictionary class]]) {
        [lines insertObject:[NSString stringWithFormat:@"Runtime: %@ · Bridge: %@ · Hermes: %@",
            [status[@"runtime"][@"ready"] boolValue] ? @"ready" : @"not ready",
            [status[@"bridge"][@"ready"] boolValue] ? @"ready" : @"not ready",
            [status[@"hermes"][@"ready"] boolValue] ? @"ready" : @"not ready"] atIndex:0];
    } else {
        NSDictionary* versions = payload[@"versions"];
        BOOL bridgeOk = [[payload valueForKeyPath:@"changed.bridgeVerify.ok"] boolValue];
        [lines insertObject:[NSString stringWithFormat:@"Runtime: %@ · Bridge: %@ · Hermes: %@",
            versions ? @"ready" : @"unknown",
            bridgeOk ? @"ready" : @"unknown",
            [versions[@"hermesVersion"][@"compatible"] boolValue] ? @"ready" : @"unknown"] atIndex:0];
    }
    return [lines componentsJoinedByString:@"\n"];
}

- (void)runTaskWithLaunchPath:(NSString*)launchPath
                    arguments:(NSArray<NSString*>*)arguments
                   completion:(void (^)(NSString* output, int exitCode, BOOL cancelled))completion {
    NSTask* task = [[NSTask alloc] init];
    [task setLaunchPath:launchPath];
    [task setArguments:arguments];

    NSPipe* pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task setStandardError:pipe];

    _activeTask = task;

    [task setTerminationHandler:^(NSTask* finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSData* data = [[pipe fileHandleForReading] readDataToEndOfFile];
            NSString* collected = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
            int code = (int)finished.terminationStatus;
            BOOL cancelled = self->_cancelRequested;
            if (self->_activeTask == finished) {
                self->_activeTask = nil;
                self->_cancelRequested = NO;
            }
            completion(collected, code, cancelled);
        });
    }];

    @try {
        [task launch];
    } @catch (NSException* exception) {
        _activeTask = nil;
        completion([NSString stringWithFormat:@"Failed to launch: %@", exception.reason], 127, NO);
    }
}

- (void)launchChatTool:(NSString*)chatPath
             arguments:(NSArray<NSString*>*)arguments
            completion:(void (^)(NSString* output, int exitCode, BOOL cancelled))completion {
    if ([chatPath hasSuffix:@".py"]) {
        NSMutableArray<NSString*>* args = [NSMutableArray arrayWithObject:chatPath];
        [args addObjectsFromArray:arguments];
        [self runTaskWithLaunchPath:@"/usr/bin/python3" arguments:args completion:completion];
        return;
    }
    [self runTaskWithLaunchPath:chatPath arguments:arguments completion:completion];
}

- (void)runDoctorWithCompletion:(void (^)(NSString* output, int exitCode))completion {
    NSString* workspace = [self workspacePath];
    NSString* chatPath = DietCodeAgentChatPath();
    if (chatPath != nil) {
        NSMutableArray<NSString*>* args = [NSMutableArray arrayWithObjects:@"--doctor", @"--format", @"json", nil];
        if (workspace.length > 0) {
            [args addObjectsFromArray:@[@"--workspace", workspace]];
        }
        [self launchChatTool:chatPath
                   arguments:args
                  completion:^(NSString* output, int exitCode, BOOL cancelled) {
            (void)cancelled;
            completion(output, exitCode);
        }];
        return;
    }
    NSString* enablePath = DietCodeEnableAgentPath();
    if (enablePath == nil) {
        completion(@"dietcode-agent-chat not found in app bundle.", 127);
        return;
    }
    [self runTaskWithLaunchPath:enablePath
                      arguments:@[@"--doctor", @"--compact"]
                     completion:^(NSString* output, int exitCode, BOOL cancelled) {
        (void)cancelled;
        completion(output, exitCode);
    }];
}

- (void)refreshStatus {
    NSString* workspace = [self workspacePath];
    [_statusLabel setStringValue:@"Status: Checking…"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self runDoctorWithCompletion:^(NSString* output, int exitCode) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString* summary = [self statusTextFromDoctorJSON:output workspace:workspace exitCode:exitCode running:NO];
                if (exitCode != 0 && ![summary containsString:@"ready"]) {
                    summary = [NSString stringWithFormat:@"Doctor exit %d\n%@", exitCode, summary];
                }
                [self->_statusLabel setStringValue:summary];
                BOOL canSend = workspace.length > 0 && self->_workspaceAuthorityMatch && !self->_runningCommand;
                [self->_sendButton setEnabled:canSend];
            });
        }];
    });
}

- (void)sendPrompt:(id)sender {
    (void)sender;
    if (_runningCommand) {
        return;
    }

    NSString* workspace = [[self workspacePath] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (workspace.length == 0) {
        [self appendTranscriptWithSpeaker:kAgentSpeakerHermes message:@"Open a folder first."];
        [_statusLabel setStringValue:@"Workspace requested: (none — open a folder)\nLast exit: —"];
        return;
    }
    if (!_workspaceAuthorityMatch) {
        [self appendTranscriptWithSpeaker:kAgentSpeakerHermes
                                  message:@"Workspace mismatch — agent disabled. Re-open the folder or check runtime workspace."];
        return;
    }

    NSString* prompt = [_inputField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (prompt.length == 0) {
        return;
    }

    NSString* chatPath = DietCodeAgentChatPath();
    if (chatPath == nil) {
        [self appendTranscriptWithSpeaker:kAgentSpeakerHermes message:@"dietcode-agent-chat not found. Reinstall DietCode.app."];
        return;
    }

    [self appendTranscriptWithSpeaker:kAgentSpeakerYou message:prompt];
    [_inputField setStringValue:@""];

    _runningCommand = YES;
    [_sendButton setEnabled:NO];
    [_stopButton setEnabled:YES];
    [_statusLabel setStringValue:[self statusTextFromDoctorJSON:@"" workspace:workspace exitCode:_lastExitCode running:YES]];

    NSArray<NSString*>* args = @[
        @"--workspace", workspace,
        @"--prompt", prompt,
        @"--format", @"text",
    ];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self launchChatTool:chatPath
                   arguments:args
                  completion:^(NSString* output, int exitCode, BOOL cancelled) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_lastExitCode = exitCode;
                if (cancelled) {
                    [self appendTranscriptWithSpeaker:kAgentSpeakerHermes message:@"Request cancelled."];
                } else if (output.length > 0) {
                    NSString* response = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if (response.length > 8000) {
                        response = [[response substringToIndex:8000] stringByAppendingString:@"\n…"];
                    }
                    if (exitCode != 0) {
                        response = [NSString stringWithFormat:@"Exit %d.\n%@", exitCode, response];
                    }
                    [self appendTranscriptWithSpeaker:kAgentSpeakerHermes message:response];
                } else {
                    [self appendTranscriptWithSpeaker:kAgentSpeakerHermes
                                              message:[NSString stringWithFormat:@"Hermes returned no output (exit %d).", exitCode]];
                }
                self->_runningCommand = NO;
                self->_activeTask = nil;
                [self->_sendButton setEnabled:YES];
                [self->_stopButton setEnabled:NO];
                [self refreshStatus];
            });
        }];
    });
}

- (void)stopPrompt:(id)sender {
    (void)sender;
    if (_activeTask != nil && _activeTask.isRunning) {
        _cancelRequested = YES;
        [_activeTask terminate];
        _runningCommand = NO;
        [_sendButton setEnabled:YES];
        [_stopButton setEnabled:NO];
        [self appendTranscriptWithSpeaker:kAgentSpeakerHermes message:@"Stopping…"];
    }
}

- (BOOL)control:(NSControl*)control textView:(NSTextView*)textView doCommandBySelector:(SEL)commandSelector {
    if (control == _inputField && commandSelector == @selector(insertNewline:)) {
        [self sendPrompt:_sendButton];
        return YES;
    }
    return NO;
}

@end
