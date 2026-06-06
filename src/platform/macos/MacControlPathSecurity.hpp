#pragma once

#import <Cocoa/Cocoa.h>
#include <filesystem>
#include <string>

namespace dietcode::platform::macos {

NSString* AbsolutePathForRPCPath(NSString* path, NSString* workspace);
BOOL PathIsInsideWorkspace(NSString* path, NSString* workspace);
BOOL AnyPatternMatches(NSArray<NSString*>* patterns, const std::string& relPath, const std::string& filename);
BOOL ShouldSkipSearchPath(const std::filesystem::path& path, const std::string& relPath, NSArray<NSString*>* includes, NSArray<NSString*>* excludes);
BOOL ShouldPruneSearchDirectory(const std::filesystem::path& path, const std::string& relPath, NSArray<NSString*>* excludes);

} // namespace dietcode::platform::macos
