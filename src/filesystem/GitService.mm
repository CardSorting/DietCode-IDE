#import <Foundation/Foundation.h>
#include "GitService.hpp"
#include <sstream>
#include <filesystem>
#include <iostream>

namespace dietcode::filesystem {

static std::string runCommand(const std::string& dir, NSString* launchPath, NSArray<NSString*>* args, int* exitCodeOut = nullptr) {
    NSTask* task = [[NSTask alloc] init];
    [task setLaunchPath:launchPath];
    [task setArguments:args];
    [task setCurrentDirectoryPath:[NSString stringWithUTF8String:dir.c_str()]];
    
    NSPipe* outPipe = [NSPipe pipe];
    NSPipe* errPipe = [NSPipe pipe];
    [task setStandardOutput:outPipe];
    [task setStandardError:errPipe];
    
    @try {
        [task launch];
        [task waitUntilExit];
        
        NSData* outData = [[outPipe fileHandleForReading] readDataToEndOfFile];
        NSString* outStr = [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding];
        
        if (exitCodeOut) {
            *exitCodeOut = task.terminationStatus;
        }
        
        if (task.terminationStatus != 0) {
            NSData* errData = [[errPipe fileHandleForReading] readDataToEndOfFile];
            NSString* errStr = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding];
            if (errStr.length > 0) {
                return std::string([errStr UTF8String]);
            }
        }
        
        return std::string([outStr UTF8String]);
    } @catch (NSException* e) {
        if (exitCodeOut) {
            *exitCodeOut = -1;
        }
        return "Failed to launch task: " + std::string([[e reason] UTF8String]);
    }
}

GitStatusResult GitService::getStatus(const std::string& workspacePath) {
    GitStatusResult result;
    result.branch = "";
    
    // Check if it is a git repository
    int exitCode = 0;
    runCommand(workspacePath, @"/usr/bin/git", @[@"rev-parse", @"--is-inside-work-tree"], &exitCode);
    if (exitCode != 0) {
        return result; // Not a git repo
    }
    
    // Get current branch
    std::string branchOut = runCommand(workspacePath, @"/usr/bin/git", @[@"symbolic-ref", @"--short", @"HEAD"], &exitCode);
    if (exitCode != 0) {
        // Detached HEAD or other issue, try rev-parse
        branchOut = runCommand(workspacePath, @"/usr/bin/git", @[@"rev-parse", @"--abbrev-ref", @"HEAD"], &exitCode);
    }
    
    // Clean branch name
    if (exitCode == 0 && !branchOut.empty()) {
        // Strip newlines
        while (!branchOut.empty() && (branchOut.back() == '\n' || branchOut.back() == '\r')) {
            branchOut.pop_back();
        }
        result.branch = branchOut;
    } else {
        result.branch = "HEAD (detached)";
    }
    
    // Get porcelain status
    std::string statusOut = runCommand(workspacePath, @"/usr/bin/git", @[@"status", @"--porcelain", @"-u"]);
    std::stringstream ss(statusOut);
    std::string line;
    while (std::getline(ss, line)) {
        if (line.length() < 4) continue;
        
        char stageChar = line[0];
        char workChar = line[1];
        std::string p = line.substr(3);
        
        // Handle renames: old_path -> new_path
        size_t renamePos = p.find(" -> ");
        if (renamePos != std::string::npos) {
            p = p.substr(renamePos + 4);
        }
        
        // Strip surrounding quotes if any
        if (p.size() >= 2 && p.front() == '"' && p.back() == '"') {
            p = p.substr(1, p.size() - 2);
        }
        
        // Staged status
        if (stageChar != ' ' && stageChar != '?') {
            GitChange change;
            change.status = std::string(1, stageChar);
            change.path = p;
            change.staged = true;
            result.changes.push_back(change);
        }
        
        // Unstaged/Worktree status
        if (workChar != ' ' || (stageChar == '?' && workChar == '?')) {
            GitChange change;
            if (stageChar == '?' && workChar == '?') {
                change.status = "??";
            } else {
                change.status = std::string(1, workChar);
            }
            change.path = p;
            change.staged = false;
            result.changes.push_back(change);
        }
    }
    
    return result;
}

bool GitService::stageFile(const std::string& workspacePath, const std::string& relativePath, std::string& errorOut) {
    int exitCode = 0;
    std::string out = runCommand(workspacePath, @"/usr/bin/git", @[@"add", [NSString stringWithUTF8String:relativePath.c_str()]], &exitCode);
    if (exitCode != 0) { errorOut = out.empty() ? "git add failed (exit " + std::to_string(exitCode) + ")" : out; }
    return exitCode == 0;
}

bool GitService::unstageFile(const std::string& workspacePath, const std::string& relativePath, std::string& errorOut) {
    int exitCode = 0;
    std::string out = runCommand(workspacePath, @"/usr/bin/git", @[@"reset", @"HEAD", [NSString stringWithUTF8String:relativePath.c_str()]], &exitCode);
    if (exitCode != 0) { errorOut = out.empty() ? "git reset HEAD failed (exit " + std::to_string(exitCode) + ")" : out; }
    return exitCode == 0;
}

bool GitService::discardChanges(const std::string& workspacePath, const std::string& relativePath, std::string& errorOut) {
    std::filesystem::path fullPath = std::filesystem::path(workspacePath) / relativePath;

    // Check if the file is untracked
    GitStatusResult status = getStatus(workspacePath);
    bool untracked = false;
    for (const auto& c : status.changes) {
        if (c.path == relativePath && c.status == "??") {
            untracked = true;
            break;
        }
    }

    if (untracked) {
        std::error_code ec;
        std::filesystem::remove(fullPath, ec);
        if (ec) { errorOut = "Failed to remove untracked file: " + ec.message(); }
        return !ec;
    } else {
        int exitCode = 0;
        std::string out = runCommand(workspacePath, @"/usr/bin/git", @[@"checkout", @"--", [NSString stringWithUTF8String:relativePath.c_str()]], &exitCode);
        if (exitCode != 0) { errorOut = out.empty() ? "git checkout failed (exit " + std::to_string(exitCode) + ")" : out; }
        return exitCode == 0;
    }
}

std::string GitService::getDiff(const std::string& workspacePath, const std::string& relativePath, bool staged) {
    // Check if the file is untracked
    GitStatusResult status = getStatus(workspacePath);
    bool untracked = false;
    for (const auto& c : status.changes) {
        if (c.path == relativePath && c.status == "??") {
            untracked = true;
            break;
        }
    }
    
    if (untracked) {
        // Diff against /dev/null for untracked files
        int exitCode = 0;
        std::string diff = runCommand(workspacePath, @"/usr/bin/git", @[
            @"diff", @"--no-index", @"/dev/null", [NSString stringWithUTF8String:relativePath.c_str()]
        ], &exitCode);
        // git diff --no-index exits with 1 if there are differences, which is normal
        return diff;
    } else {
        int exitCode = 0;
        NSArray* args = nil;
        if (staged) {
            args = @[@"diff", @"--cached", @"--", [NSString stringWithUTF8String:relativePath.c_str()]];
        } else {
            args = @[@"diff", @"--", [NSString stringWithUTF8String:relativePath.c_str()]];
        }
        return runCommand(workspacePath, @"/usr/bin/git", args, &exitCode);
    }
}

bool GitService::commit(const std::string& workspacePath, const std::string& message, std::string& errorOut) {
    int exitCode = 0;
    std::string out = runCommand(workspacePath, @"/usr/bin/git", @[
        @"commit", @"-m", [NSString stringWithUTF8String:message.c_str()]
    ], &exitCode);
    
    if (exitCode != 0) {
        errorOut = out;
        return false;
    }
    return true;
}

} // namespace dietcode::filesystem
