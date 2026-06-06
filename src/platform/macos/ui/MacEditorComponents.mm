#import "MacEditorComponents.hpp"
#import "MacWindow.hpp"
#import "MacWindow+Private.hpp"

#include <util.h>
#include <unistd.h>

@implementation DietCodeLineNumberRulerView

- (instancetype)initWithScrollView:(NSScrollView*)scrollView {
    self = [super initWithScrollView:scrollView orientation:NSVerticalRuler];
    if (self) {
        self.clientView = scrollView.documentView;
        self.ruleThickness = 45.0;
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(rulerNeedsDisplay:)
                                                     name:NSViewBoundsDidChangeNotification
                                                   object:scrollView.contentView];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(rulerNeedsDisplay:)
                                                     name:NSTextDidChangeNotification
                                                   object:scrollView.documentView];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)rulerNeedsDisplay:(NSNotification*)notification {
    [self setNeedsDisplay:YES];
}

- (void)drawHashMarksAndLabelsInRect:(NSRect)rect {
    NSTextView* textView = (NSTextView*)self.clientView;
    if (![textView isKindOfClass:[NSTextView class]]) {
        return;
    }
    
    NSLayoutManager* layoutManager = textView.layoutManager;
    NSTextContainer* textContainer = textView.textContainer;
    NSString* content = textView.string;
    
    BOOL isDark = NO;
    if (@available(macOS 10.14, *)) {
        NSAppearanceName appearance = [NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        isDark = [appearance isEqualToString:NSAppearanceNameDarkAqua];
    }
    
    if (isDark) {
        [[NSColor colorWithCalibratedWhite:0.15 alpha:1.0] set];
    } else {
        [[NSColor colorWithCalibratedWhite:0.96 alpha:1.0] set];
    }
    NSRectFill(self.bounds);
    
    NSRect visibleRect = [self.scrollView.contentView bounds];
    NSPoint containerOrigin = textView.textContainerOrigin;
    NSRect textRect = NSOffsetRect(visibleRect, -containerOrigin.x, -containerOrigin.y);
    
    NSRange glyphRange = [layoutManager glyphRangeForBoundingRect:textRect inTextContainer:textContainer];
    NSRange charRange = [layoutManager characterRangeForGlyphRange:glyphRange actualGlyphRange:NULL];
    
    if (charRange.length == 0 && content.length > 0) {
        return;
    }
    
    NSUInteger lineNumber = 1;
    for (NSUInteger i = 0; i < charRange.location && i < content.length; i++) {
        if ([content characterAtIndex:i] == '\n') {
            lineNumber++;
        }
    }
    
    NSDictionary* attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11],
        NSForegroundColorAttributeName: isDark ? [NSColor colorWithCalibratedWhite:0.5 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.4 alpha:1.0]
    };
    
    NSUInteger index = charRange.location;
    while (index < NSMaxRange(charRange)) {
        NSRange lineRange = [content lineRangeForRange:NSMakeRange(index, 0)];
        NSRange glyphLineRange = [layoutManager glyphRangeForCharacterRange:lineRange actualCharacterRange:NULL];
        
        NSUInteger rectCount = 0;
        NSRectArray rects = [layoutManager rectArrayForGlyphRange:glyphLineRange
                                          withinSelectedGlyphRange:NSMakeRange(NSNotFound, 0)
                                                   inTextContainer:textContainer
                                                         rectCount:&rectCount];
        
        if (rectCount > 0) {
            CGFloat y = rects[0].origin.y + containerOrigin.y - visibleRect.origin.y;
            NSString* numStr = [NSString stringWithFormat:@"%lu", (unsigned long)lineNumber];
            NSSize size = [numStr sizeWithAttributes:attrs];
            NSRect textFrame = NSMakeRect(self.ruleThickness - size.width - 8, y + 2, size.width, size.height);
            [numStr drawInRect:textFrame withAttributes:attrs];
            
            // Draw diagnostic dot if needed
            DietCodeWindowController* controller = (DietCodeWindowController*)self.scrollView.window.windowController;
            if (controller && [controller respondsToSelector:@selector(diagnosticsForTabPath:lineNumber:)]) {
                id activeTab = [((id)controller) activeTab];
                NSString* tabPath = [activeTab respondsToSelector:@selector(path)] ? [activeTab path] : nil;
                NSArray* lineDiags = [controller diagnosticsForTabPath:tabPath lineNumber:lineNumber];
                if (lineDiags.count > 0) {
                    BOOL hasError = NO;
                    for (NSDictionary* d in lineDiags) {
                        if ([d[@"severity"] isEqualToString:@"error"]) {
                            hasError = YES;
                            break;
                        }
                    }
                    NSColor* color = hasError ? [NSColor systemRedColor] : [NSColor systemYellowColor];
                    [color set];
                    NSRect dotRect = NSMakeRect(6, y + 6, 6, 6);
                    NSBezierPath* dotPath = [NSBezierPath bezierPathWithOvalInRect:dotRect];
                    [dotPath fill];
                }
            }
        }
        
        lineNumber++;
        index = NSMaxRange(lineRange);
    }
    
    if (NSMaxRange(charRange) == content.length && content.length > 0 && [content characterAtIndex:content.length - 1] == '\n') {
        NSRange endRange = NSMakeRange(content.length, 0);
        NSRange glyphEndRange = [layoutManager glyphRangeForCharacterRange:endRange actualCharacterRange:NULL];
        NSRect lineRect = [layoutManager lineFragmentUsedRectForGlyphAtIndex:glyphEndRange.location effectiveRange:NULL];
        CGFloat y = lineRect.origin.y + containerOrigin.y - visibleRect.origin.y;
        NSString* numStr = [NSString stringWithFormat:@"%lu", (unsigned long)lineNumber];
        NSSize size = [numStr sizeWithAttributes:attrs];
        NSRect textFrame = NSMakeRect(self.ruleThickness - size.width - 8, y + 2, size.width, size.height);
        [numStr drawInRect:textFrame withAttributes:attrs];
        
        DietCodeWindowController* controller = (DietCodeWindowController*)self.scrollView.window.windowController;
        if (controller && [controller respondsToSelector:@selector(diagnosticsForTabPath:lineNumber:)]) {
            id activeTab = [((id)controller) activeTab];
            NSString* tabPath = [activeTab respondsToSelector:@selector(path)] ? [activeTab path] : nil;
            NSArray* lineDiags = [controller diagnosticsForTabPath:tabPath lineNumber:lineNumber];
            if (lineDiags.count > 0) {
                BOOL hasError = NO;
                for (NSDictionary* d in lineDiags) {
                    if ([d[@"severity"] isEqualToString:@"error"]) {
                        hasError = YES;
                        break;
                    }
                }
                NSColor* color = hasError ? [NSColor systemRedColor] : [NSColor systemYellowColor];
                [color set];
                NSRect dotRect = NSMakeRect(6, y + 6, 6, 6);
                NSBezierPath* dotPath = [NSBezierPath bezierPathWithOvalInRect:dotRect];
                [dotPath fill];
            }
        }
    }
}

@end

@implementation DietCodeOutlineView
- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 36) { // Return key
        NSInteger row = [self selectedRow];
        if (row >= 0) {
            id target = [self target];
            SEL action = [self doubleAction];
            if (target && action && [target respondsToSelector:action]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [target performSelector:action withObject:self];
#pragma clang diagnostic pop
                return;
            }
        }
    }
    [super keyDown:event];
}
@end

@implementation DietCodeTabState
@end

@implementation DietCodeNavigationTextView
- (void)mouseDown:(NSEvent *)event {
    [super mouseDown:event];
    if (event.clickCount == 2) {
        NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
        NSLayoutManager *layoutManager = self.layoutManager;
        NSTextContainer *textContainer = self.textContainer;
        NSPoint containerPoint = NSMakePoint(point.x - self.textContainerOrigin.x, point.y - self.textContainerOrigin.y);
        
        NSUInteger glyphIndex = [layoutManager glyphIndexForPoint:containerPoint inTextContainer:textContainer];
        NSRect glyphRect = [layoutManager lineFragmentUsedRectForGlyphAtIndex:glyphIndex effectiveRange:NULL];
        if (!NSPointInRect(containerPoint, glyphRect)) {
            return;
        }
        
        NSUInteger charIndex = [layoutManager characterIndexForGlyphAtIndex:glyphIndex];
        if (charIndex < self.string.length) {
            NSRange lineRange = [self.string lineRangeForRange:NSMakeRange(charIndex, 0)];
            NSString *line = [self.string substringWithRange:lineRange];
            line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            
            // Calculate line index
            NSUInteger lineIndex = 0;
            NSString* str = self.string;
            for (NSUInteger i = 0; i < charIndex; i++) {
                if ([str characterAtIndex:i] == '\n') {
                    lineIndex++;
                }
            }
            
            if (self.navigationTarget && [self.navigationTarget respondsToSelector:@selector(navigateFromProblemsLineIndex:sender:)]) {
                [self.navigationTarget performSelector:@selector(navigateFromProblemsLineIndex:sender:) withObject:@(lineIndex) withObject:self];
            } else if (self.navigationTarget && [self.navigationTarget respondsToSelector:@selector(navigateFromProblemsOrSearchText:sender:)]) {
                [self.navigationTarget performSelector:@selector(navigateFromProblemsOrSearchText:sender:) withObject:line withObject:self];
            }
        }
    }
}
@end

@implementation DietCodeEditorTextView
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea* area in self.trackingAreas) {
        [self removeTrackingArea:area];
    }
    
    NSTrackingAreaOptions options = NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp | NSTrackingInVisibleRect;
    NSTrackingArea* area = [[NSTrackingArea alloc] initWithRect:self.bounds options:options owner:self userInfo:nil];
    [self addTrackingArea:area];
}

- (void)mouseMoved:(NSEvent *)event {
    [super mouseMoved:event];
    DietCodeWindowController* controller = (DietCodeWindowController*)self.window.windowController;
    if (controller && [controller respondsToSelector:@selector(handleMouseHoverInTextView:atPoint:)]) {
        NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
        [controller handleMouseHoverInTextView:self atPoint:point];
    }
}
@end

@implementation DietCodeTerminalTextView

- (void)keyDown:(NSEvent*)event {
    NSString* chars = event.characters;
    if (chars.length > 0 && self.masterFd >= 0) {
        const char* utf8 = [chars UTF8String];
        write(self.masterFd, utf8, strlen(utf8));
    }
}

- (void)insertText:(id)insertString replacementRange:(NSRange)replacementRange {
    if ([insertString isKindOfClass:[NSString class]] && self.masterFd >= 0) {
        const char* utf8 = [insertString UTF8String];
        write(self.masterFd, utf8, strlen(utf8));
    }
}

@end

@implementation DietCodeCommandPalettePanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end
