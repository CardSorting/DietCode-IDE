#pragma once

#import <Cocoa/Cocoa.h>

@protocol DietCodeAgentSidebarDelegate <NSObject>
- (NSString*)agentSidebarWorkspacePath;
@end

/// Right-side Agent Chat sidebar — real Hermes chat via bundled dietcode-agent-chat.
@interface DietCodeAgentSidebarView : NSView <NSTextFieldDelegate>

@property(nonatomic, weak) id<DietCodeAgentSidebarDelegate> delegate;
@property(nonatomic, strong, readonly) NSTextField* statusLabel;
@property(nonatomic, strong, readonly) NSTextView* transcriptView;
@property(nonatomic, strong, readonly) NSTextField* inputField;
@property(nonatomic, strong, readonly) NSButton* sendButton;
@property(nonatomic, strong, readonly) NSButton* stopButton;

- (void)appendTranscriptWithSpeaker:(NSString*)speaker message:(NSString*)message;
- (void)refreshStatus;
- (void)sendPrompt:(id)sender;
- (void)stopPrompt:(id)sender;

@end
