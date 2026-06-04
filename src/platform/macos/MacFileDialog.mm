#include "MacFileDialog.hpp"

#import <Cocoa/Cocoa.h>

namespace dietcode::platform::macos {

std::optional<std::filesystem::path> MacFileDialog::openFile() {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setAllowsMultipleSelection:NO];
    [panel setMessage:@"Choose a file to edit in DietCode."];

    if ([panel runModal] != NSModalResponseOK) {
        return std::nullopt;
    }

    NSURL* url = [[panel URLs] firstObject];
    if (url == nil || [url path] == nil) {
        return std::nullopt;
    }

    return std::filesystem::path([[url path] UTF8String]);
}

std::optional<std::filesystem::path> MacFileDialog::saveFile() {
    NSSavePanel* panel = [NSSavePanel savePanel];
    [panel setCanCreateDirectories:YES];
    [panel setMessage:@"Choose where to save this file."];
    [panel setNameFieldStringValue:@"Untitled.txt"];

    if ([panel runModal] != NSModalResponseOK) {
        return std::nullopt;
    }

    NSURL* url = [panel URL];
    if (url == nil || [url path] == nil) {
        return std::nullopt;
    }

    return std::filesystem::path([[url path] UTF8String]);
}

} // namespace dietcode::platform::macos
