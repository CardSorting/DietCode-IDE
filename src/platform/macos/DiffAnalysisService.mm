#import "DiffAnalysisService.hpp"
#include <unistd.h>
#include <stdlib.h>
#include <iostream>
#include <vector>

namespace {
NSString* runGitCmd(NSString* dir, NSArray<NSString*>* args) {
    NSTask* task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/git"];
    [task setArguments:args];
    [task setCurrentDirectoryPath:dir];

    NSPipe* outPipe = [NSPipe pipe];
    [task setStandardOutput:outPipe];
    [task setStandardError:outPipe];

    @try {
        [task launch];
        NSData* data = [[outPipe fileHandleForReading] readDataToEndOfFile];
        [task waitUntilExit];
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    } @catch (NSException* e) {
        return @"";
    }
}

BOOL checkBracketBalance(NSString* text) {
    std::vector<unichar> stack;
    NSUInteger len = text.length;
    for (NSUInteger i = 0; i < len; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == '(' || c == '[' || c == '{') {
            stack.push_back(c);
        } else if (c == ')') {
            if (stack.empty() || stack.back() != '(') return NO;
            stack.pop_back();
        } else if (c == ']') {
            if (stack.empty() || stack.back() != '[') return NO;
            stack.pop_back();
        } else if (c == '}') {
            if (stack.empty() || stack.back() != '{') return NO;
            stack.pop_back();
        }
    }
    return stack.empty();
}
}

@implementation DietCodeDiffAnalysisService

+ (NSDictionary*)workspaceDiffInfo:(NSString*)ws {
    NSMutableDictionary* result = [NSMutableDictionary dictionary];
    if (ws.length == 0) return result;

    // Run git diff --numstat for unstaged changes
    NSString* numstatUnstaged = runGitCmd(ws, @[@"diff", @"--numstat"]);
    // Run git diff --numstat --cached for staged changes
    NSString* numstatStaged = runGitCmd(ws, @[@"diff", @"--cached", @"--numstat"]);

    NSMutableDictionary* filesInfo = [NSMutableDictionary dictionary];

    auto parseNumstat = ^(NSString* output, BOOL staged) {
        NSArray<NSString*>* lines = [output componentsSeparatedByString:@"\n"];
        for (NSString* line in lines) {
            NSArray<NSString*>* parts = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSMutableArray<NSString*>* cleanParts = [NSMutableArray array];
            for (NSString* p in parts) {
                if (p.length > 0) [cleanParts addObject:p];
            }
            if (cleanParts.count >= 3) {
                NSInteger added = [cleanParts[0] integerValue];
                NSInteger deleted = [cleanParts[1] integerValue];
                NSString* filePath = cleanParts[2];

                NSMutableDictionary* fileMeta = filesInfo[filePath] ?: [NSMutableDictionary dictionary];
                fileMeta[@"added"] = @([fileMeta[@"added"] integerValue] + added);
                fileMeta[@"deleted"] = @([fileMeta[@"deleted"] integerValue] + deleted);
                if (staged) {
                    fileMeta[@"staged"] = @YES;
                } else {
                    fileMeta[@"unstaged"] = @YES;
                }
                filesInfo[filePath] = fileMeta;
            }
        }
    };

    parseNumstat(numstatUnstaged, NO);
    parseNumstat(numstatStaged, YES);

    NSMutableArray* filesArr = [NSMutableArray array];
    NSInteger totalAdded = 0;
    NSInteger totalDeleted = 0;

    for (NSString* filePath in filesInfo) {
        NSDictionary* meta = filesInfo[filePath];
        totalAdded += [meta[@"added"] integerValue];
        totalDeleted += [meta[@"deleted"] integerValue];
        [filesArr addObject:@{
            @"path": filePath,
            @"added": meta[@"added"] ?: @0,
            @"deleted": meta[@"deleted"] ?: @0,
            @"staged": meta[@"staged"] ?: @NO,
            @"unstaged": meta[@"unstaged"] ?: @NO
        }];
    }

    result[@"files"] = filesArr;
    result[@"totalAdded"] = @(totalAdded);
    result[@"totalDeleted"] = @(totalDeleted);

    return result;
}

+ (NSDictionary*)previewPatchAtPath:(NSString*)path
                              patch:(NSString*)patch
                        currentText:(NSString*)currentText
                            symbols:(NSArray<NSDictionary*>*)symbols {

    NSMutableDictionary* result = [NSMutableDictionary dictionary];

    // Setup temp files
    NSString* tempDir = NSTemporaryDirectory() ?: @"/tmp";
    NSString* tempSrcPath = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"dietcode_preview_src_%u.txt", arc4random()]];
    NSString* tempDiffPath = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"dietcode_preview_diff_%u.diff", arc4random()]];

    NSError* err = nil;
    unlink([tempSrcPath UTF8String]);
    [currentText writeToFile:tempSrcPath atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (err) {
        return @{ @"ok": @NO, @"error": @"Failed to write temp source." };
    }
    unlink([tempDiffPath UTF8String]);
    [patch writeToFile:tempDiffPath atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (err) {
        [[NSFileManager defaultManager] removeItemAtPath:tempSrcPath error:nil];
        return @{ @"ok": @NO, @"error": @"Failed to write temp diff patch." };
    }

    // Run patch --silent
    NSTask* task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/patch"];
    [task setArguments:@[@"--silent", tempSrcPath, tempDiffPath]];

    NSPipe* errPipe = [NSPipe pipe];
    [task setStandardError:errPipe];
    [task setStandardOutput:errPipe];

    [task launch];
    NSData* errData = [[errPipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];

    int status = [task terminationStatus];
    if (status != 0) {
        NSString* errMsg = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding];
        [[NSFileManager defaultManager] removeItemAtPath:tempSrcPath error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:tempDiffPath error:nil];

        return @{
            @"ok": @NO,
            @"risk": @"high",
            @"error": [NSString stringWithFormat:@"Patch simulation failed: %@", errMsg]
        };
    }

    NSString* patchedText = [NSString stringWithContentsOfFile:tempSrcPath encoding:NSUTF8StringEncoding error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:tempSrcPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:tempDiffPath error:nil];

    if (!patchedText) {
        return @{ @"ok": @NO, @"error": @"Failed to read patched output." };
    }

    // Parse patch to count added/removed lines and identify modified line numbers
    NSInteger addedLines = 0;
    NSInteger removedLines = 0;

    NSError* regErr = nil;
    NSRegularExpression* hunkRegex = [NSRegularExpression regularExpressionWithPattern:@"^@@ -(\\d+),?(\\d*) \\+(\\d+),?(\\d*) @@" options:0 error:&regErr];

    NSArray<NSString*>* patchLines = [patch componentsSeparatedByString:@"\n"];
    NSInteger currentNewLine = 0;
    NSMutableSet* modifiedLines = [NSMutableSet set];

    for (NSString* line in patchLines) {
        if ([line hasPrefix:@"@@"]) {
            NSTextCheckingResult* match = [hunkRegex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
            if (match) {
                currentNewLine = [[line substringWithRange:[match rangeAtIndex:3]] integerValue];
            }
        } else if (currentNewLine > 0) {
            if ([line hasPrefix:@"+"]) {
                addedLines++;
                [modifiedLines addObject:@(currentNewLine)];
                currentNewLine++;
            } else if ([line hasPrefix:@"-"]) {
                removedLines++;
                [modifiedLines addObject:@(currentNewLine)];
            } else if ([line hasPrefix:@" "]) {
                currentNewLine++;
            }
        }
    }

    // Determine which functions/symbols were touched
    NSMutableSet* touchedFunctions = [NSMutableSet set];
    for (NSDictionary* sym in symbols) {
        NSInteger sLine = [sym[@"line"] integerValue];
        NSInteger eLine = [sym[@"endLine"] integerValue];
        for (NSNumber* mLine in modifiedLines) {
            if ([mLine integerValue] >= sLine && [mLine integerValue] <= eLine) {
                [touchedFunctions addObject:sym[@"name"]];
                break;
            }
        }
    }

    // Assess risk level
    NSString* risk = @"low";
    double changeRatio = (double)(addedLines + removedLines) / (double)(currentText.length > 0 ? [currentText componentsSeparatedByString:@"\n"].count : 1);
    if ((addedLines + removedLines) > 200 || changeRatio > 0.5 || [[path lastPathComponent] isEqualToString:@"Makefile"]) {
        risk = @"high";
    } else if ((addedLines + removedLines) > 50 || changeRatio > 0.15 || touchedFunctions.count > 2) {
        risk = @"medium";
    }

    // Bracket-matching syntax safety check
    BOOL syntaxDanger = !checkBracketBalance(patchedText);
    NSString* syntaxErrors = @"";

    // Python-specific compile check
    if ([[path lowercaseString] hasSuffix:@".py"]) {
        NSString* tempPyPath = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"dietcode_syntax_check_%u.py", arc4random()]];
        unlink([tempPyPath UTF8String]);
        [patchedText writeToFile:tempPyPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

        NSTask* pyTask = [[NSTask alloc] init];
        [pyTask setLaunchPath:@"/usr/bin/python3"];
        [pyTask setArguments:@[@"-m", @"py_compile", tempPyPath]];

        NSPipe* pyErr = [NSPipe pipe];
        [pyTask setStandardError:pyErr];
        [pyTask setStandardOutput:pyErr];

        @try {
            [pyTask launch];
            NSData* errData = [[pyErr fileHandleForReading] readDataToEndOfFile];
            [pyTask waitUntilExit];
            if ([pyTask terminationStatus] != 0) {
                syntaxDanger = YES;
                syntaxErrors = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding] ?: @"Python compile failed.";
            }
        } @catch (NSException* e) {
            // python3 not available
        }
        [[NSFileManager defaultManager] removeItemAtPath:tempPyPath error:nil];
    }

    result[@"ok"] = @YES;
    result[@"addedLines"] = @(addedLines);
    result[@"removedLines"] = @(removedLines);
    result[@"functionsTouched"] = [touchedFunctions allObjects];
    result[@"risk"] = risk;
    result[@"syntaxDanger"] = @(syntaxDanger);
    result[@"syntaxErrors"] = syntaxErrors;

    return result;
}

@end
