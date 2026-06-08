#import "MacWindow+Private.hpp"
#import "MacAgentSidebar.hpp"

@interface DietCodeWindowController (AgentSidebarDelegate) <DietCodeAgentSidebarDelegate>
@end

@implementation DietCodeWindowController (AgentSidebar)

- (NSString*)agentSidebarWorkspacePath {
    return self.openedFolderPath;
}

- (void)setupAgentSidebar {
    self.agentSidebarView = [[DietCodeAgentSidebarView alloc] init];
    self.agentSidebarView.delegate = self;
    [self.agentSidebarView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.agentSidebarView.widthAnchor constraintGreaterThanOrEqualToConstant:320].active = YES;
    [self.agentSidebarView.widthAnchor constraintLessThanOrEqualToConstant:380].active = YES;
    [self.horizontalSplit addSubview:self.agentSidebarView];
    [self.horizontalSplit setHoldingPriority:NSLayoutPriorityDefaultLow + 1 forSubviewAtIndex:self.horizontalSplit.subviews.count - 1];
    self.agentSidebarView.hidden = YES;
}

- (void)toggleAgentSidebar:(id)sender {
    (void)sender;
    if (self.agentSidebarView == nil) {
        return;
    }

    if (self.agentSidebarView.isHidden) {
        self.agentSidebarView.hidden = NO;
        CGFloat width = NSWidth(self.horizontalSplit.bounds);
        if (width > 400.0) {
            [self.horizontalSplit setPosition:MAX(width - 350.0, width * 0.65) ofDividerAtIndex:2];
        }
        [self.agentSidebarView refreshStatus];
    } else {
        self.agentSidebarView.hidden = YES;
        [self.horizontalSplit setPosition:NSWidth(self.horizontalSplit.bounds) ofDividerAtIndex:2];
    }
}

@end
