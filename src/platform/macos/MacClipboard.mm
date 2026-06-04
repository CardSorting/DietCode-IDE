#include "platform/macos/MacClipboard.hpp"

#import <Cocoa/Cocoa.h>

namespace dietcode::platform::macos {

void MacClipboard::setText(const std::string& text) {
    NSPasteboard* pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    NSString* string = [NSString stringWithUTF8String:text.c_str()];
    if (string != nil) {
        [pasteboard setString:string forType:NSPasteboardTypeString];
    }
}

std::string MacClipboard::text() const {
    NSString* string = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
    if (string == nil) {
        return {};
    }
    return std::string([string UTF8String]);
}

} // namespace dietcode::platform::macos
