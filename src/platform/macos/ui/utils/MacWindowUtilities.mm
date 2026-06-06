#import "MacWindowUtilities.hpp"

namespace dietcode::platform::macos {

NSString* NSStringFromStdString(const std::string& value) {
    return [NSString stringWithUTF8String:value.c_str()] ?: @"";
}

std::string StdStringFromNSString(NSString* value) {
    if (value == nil) {
        return {};
    }
    return std::string([value UTF8String]);
}

NSTextField* MakeLabel(NSString* text, CGFloat fontSize, NSFontWeight weight) {
    NSTextField* label = [NSTextField labelWithString:text];
    [label setFont:[NSFont systemFontOfSize:fontSize weight:weight]];
    [label setLineBreakMode:NSLineBreakByWordWrapping];
    [label setMaximumNumberOfLines:0];
    return label;
}

NSButton* MakeButton(NSString* title, id target, SEL action) {
    NSButton* button = [NSButton buttonWithTitle:title target:target action:action];
    [button setBezelStyle:NSBezelStyleRounded];
    [button setControlSize:NSControlSizeLarge];
    return button;
}

NSString* FindBinaryPath(NSString* name, NSString* fallback) {
    NSArray<NSString*>* searchPaths = @[
        @"/usr/bin",
        @"/usr/local/bin",
        @"/opt/homebrew/bin"
    ];
    for (NSString* dir in searchPaths) {
        NSString* fullPath = [dir stringByAppendingPathComponent:name];
        if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath]) {
            return fullPath;
        }
    }
    return fallback;
}

NSString* StableMessageHash(NSString* value) {
    uint64_t hash = 1469598103934665603ULL;
    NSData* data = [value dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    const unsigned char* bytes = (const unsigned char*)data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) {
        hash ^= bytes[i];
        hash *= 1099511628211ULL;
    }
    char buffer[17];
    snprintf(buffer, sizeof(buffer), "%016llx", (unsigned long long)hash);
    return [NSString stringWithUTF8String:buffer];
}

NSString* StableDiagnosticId(NSString* source, NSString* path, NSNumber* line, NSNumber* column, NSString* message) {
    return [NSString stringWithFormat:@"%@:%@:%@:%@:%@",
            source ?: @"unknown",
            path ?: @"",
            line ?: @(1),
            column ?: @(1),
            StableMessageHash(message ?: @"")];
}

} // namespace dietcode::platform::macos
