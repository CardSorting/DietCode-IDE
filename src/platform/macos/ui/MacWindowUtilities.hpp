#pragma once

#import <Cocoa/Cocoa.h>
#include <string>

namespace dietcode::platform::macos {

NSString* NSStringFromStdString(const std::string& value);
std::string StdStringFromNSString(NSString* value);

NSTextField* MakeLabel(NSString* text, CGFloat fontSize, NSFontWeight weight);
NSButton* MakeButton(NSString* title, id target, SEL action);

NSString* FindBinaryPath(NSString* name, NSString* fallback);

NSString* StableMessageHash(NSString* value);
NSString* StableDiagnosticId(NSString* source, NSString* path, NSNumber* line, NSNumber* column, NSString* message);

} // namespace dietcode::platform::macos
