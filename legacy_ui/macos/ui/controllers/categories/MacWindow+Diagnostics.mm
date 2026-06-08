#import "MacWindow+Private.hpp"
#import "MacWindowUtilities.hpp"
#import "MacEditorComponents.hpp"

using namespace dietcode::platform::macos;

@implementation DietCodeWindowController (Diagnostics)

- (void)setupErrorsUI {
    // Already set up in buildBottomTabViews, but we could add specific panel configuration here.
}

- (void)handleDiagnostics:(NSArray*)newDiags forFile:(NSString*)filePath source:(NSString*)source {
    if (!filePath) return;
    
    NSMutableArray* currentList = self.diagnosticsDict[filePath];
    if (!currentList) {
        currentList = [NSMutableArray array];
        self.diagnosticsDict[filePath] = currentList;
    }
    
    NSMutableArray* toRemove = [NSMutableArray array];
    for (NSDictionary* d in currentList) {
        if ([d[@"source"] isEqualToString:source]) {
            [toRemove addObject:d];
        }
    }
    [currentList removeObjectsInArray:toRemove];
    
    for (NSDictionary* d in newDiags) {
        NSMutableDictionary* md = [d mutableCopy];
        md[@"source"] = source;
        [currentList addObject:md];
    }
    
    for (DietCodeTabState* tab in self.openTabs) {
        if ([tab.path isEqualToString:filePath]) {
            [self updateDiagnosticsHighlightsForTab:tab];
        }
    }
    
    [self rebuildProblemsPanel];
}

- (NSArray*)diagnosticsForTabPath:(NSString*)path lineNumber:(NSUInteger)line {
    if (!path) return nil;
    NSArray* list = self.diagnosticsDict[path];
    if (!list) return nil;
    NSMutableArray* matches = [NSMutableArray array];
    for (NSDictionary* diag in list) {
        if ([diag[@"line"] unsignedIntegerValue] == line) {
            [matches addObject:diag];
        }
    }
    return matches.count > 0 ? matches : nil;
}

- (void)updateDiagnosticsHighlightsForTab:(DietCodeTabState*)tab {
    if (!tab || !tab.textView || !tab.path || tab.isLargeFile) return;
    
    NSTextStorage* storage = tab.textView.textStorage;
    NSLayoutManager* lm = tab.textView.layoutManager;
    NSRange fullRange = NSMakeRange(0, storage.length);
    
    [lm removeTemporaryAttribute:NSUnderlineStyleAttributeName forCharacterRange:fullRange];
    [lm removeTemporaryAttribute:NSUnderlineColorAttributeName forCharacterRange:fullRange];
    
    if (!self.currentDiagnosticsEnabled) {
        [tab.scrollView.verticalRulerView setNeedsDisplay:YES];
        return;
    }
    
    NSArray* list = self.diagnosticsDict[tab.path];
    if (!list || list.count == 0) {
        [tab.scrollView.verticalRulerView setNeedsDisplay:YES];
        return;
    }
    
    NSString* content = [tab.textView string];
    NSUInteger len = content.length;
    
    for (NSDictionary* diag in list) {
        NSInteger line = [diag[@"line"] integerValue];
        NSInteger col = [diag[@"column"] integerValue];
        NSString* severity = diag[@"severity"];
        
        NSUInteger charIndex = 0;
        NSUInteger currentLine = 1;
        while (charIndex < len && currentLine < (NSUInteger)line) {
            if ([content characterAtIndex:charIndex] == '\n') {
                currentLine++;
            }
            charIndex++;
        }
        
        if (charIndex < len) {
            charIndex += (col > 0 ? (col - 1) : 0);
        }
        if (charIndex >= len) {
            charIndex = len > 0 ? len - 1 : 0;
        }
        
        if (charIndex >= len) continue;

        NSRange lineRange = [content lineRangeForRange:NSMakeRange(charIndex, 0)];
        NSRange underlineRange = NSMakeRange(charIndex, 1);
        
        if (charIndex < len) {
            NSCharacterSet* wordChars = [NSCharacterSet alphanumericCharacterSet];
            NSUInteger endIdx = charIndex;
            while (endIdx < NSMaxRange(lineRange) && [wordChars characterIsMember:[content characterAtIndex:endIdx]]) {
                endIdx++;
            }
            if (endIdx > charIndex) {
                underlineRange = NSMakeRange(charIndex, endIdx - charIndex);
            }
        }
        
        if (underlineRange.location + underlineRange.length <= len) {
            NSColor* color = [severity isEqualToString:@"error"] ? [NSColor systemRedColor] : [NSColor systemYellowColor];
            [lm addTemporaryAttribute:NSUnderlineStyleAttributeName 
                                value:@(NSUnderlineStyleSingle | NSUnderlineStylePatternDot) 
                    forCharacterRange:underlineRange];
            [lm addTemporaryAttribute:NSUnderlineColorAttributeName 
                                value:color 
                    forCharacterRange:underlineRange];
        }
    }
    
    [tab.scrollView.verticalRulerView setNeedsDisplay:YES];
}

- (void)rebuildProblemsPanel {
    [self.unifiedDiagnostics removeAllObjects];
    NSMutableString* problemText = [NSMutableString string];
    NSUInteger totalProblems = 0;
    
    NSMutableSet* seenProblems = [NSMutableSet set];
    
    NSArray* filePaths = [[self.diagnosticsDict allKeys] sortedArrayUsingSelector:@selector(compare:)];
    
    for (NSString* filePath in filePaths) {
        NSArray* fileDiags = self.diagnosticsDict[filePath];
        if (fileDiags.count == 0) continue;
        
        for (NSDictionary* diag in fileDiags) {
            NSInteger line = [diag[@"line"] integerValue];
            NSInteger col = [diag[@"column"] integerValue];
            NSString* msg = diag[@"message"];
            NSString* severity = diag[@"severity"];
            
            NSString* dupKey = [NSString stringWithFormat:@"%@:%ld:%@", filePath, (long)line, msg];
            if ([seenProblems containsObject:dupKey]) {
                continue;
            }
            [seenProblems addObject:dupKey];
            
            totalProblems++;
            
            NSString* prefix = @"[INFO]";
            if ([severity isEqualToString:@"error"]) {
                prefix = @"[ERROR]";
            } else if ([severity isEqualToString:@"warning"]) {
                prefix = @"[WARNING]";
            }
            
            NSString* displayPath = filePath;
            if (self.openedFolderPath && [filePath hasPrefix:self.openedFolderPath]) {
                displayPath = [filePath substringFromIndex:self.openedFolderPath.length];
                if ([displayPath hasPrefix:@"/"]) {
                    displayPath = [displayPath substringFromIndex:1];
                }
            }
            
            [problemText appendFormat:@"%@ %@:%ld:%ld - %@\n", prefix, displayPath, (long)line, (long)col, msg];
            
            [self.unifiedDiagnostics addObject:@{
                @"path": filePath,
                @"line": @(line),
                @"column": @(col),
                @"severity": severity,
                @"message": msg,
                @"source": diag[@"source"] ?: @"unknown"
            }];
        }
    }
    
    [self.errorsTextView setString:problemText];
    [self updatePlaceholderVisibility:self.errorsTextView];
    
    for (NSTabViewItem* item in self.bottomTabView.tabViewItems) {
        if ([item.identifier isEqualToString:@"errors"]) {
            if (totalProblems > 0) {
                item.label = [NSString stringWithFormat:@"Problems (%lu)", (unsigned long)totalProblems];
            } else {
                item.label = @"Problems";
            }
            break;
        }
    }
}

- (NSArray*)parseCompilerOutput:(NSString*)output {
    NSMutableArray* parsed = [NSMutableArray array];
    if (output.length == 0) return parsed;
    
    NSError* error = nil;
    NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:@"^([^:\\n]+):([0-9]+):(?:([0-9]+):)? (error|warning|info|note): (.*)$"
                                                                           options:NSRegularExpressionAnchorsMatchLines
                                                                             error:&error];
    if (error) return parsed;
    
    NSArray* matches = [regex matchesInString:output options:0 range:NSMakeRange(0, output.length)];
    for (NSTextCheckingResult* match in matches) {
        if (match.numberOfRanges >= 6) {
            NSString* file = [output substringWithRange:[match rangeAtIndex:1]];
            NSString* lineStr = [output substringWithRange:[match rangeAtIndex:2]];
            NSString* colStr = [match rangeAtIndex:3].location != NSNotFound ? [output substringWithRange:[match rangeAtIndex:3]] : @"1";
            NSString* severity = [[output substringWithRange:[match rangeAtIndex:4]] isEqualToString:@"note"] ? @"info" : [output substringWithRange:[match rangeAtIndex:4]];
            NSString* msg = [output substringWithRange:[match rangeAtIndex:5]];
            
            NSString* absPath = [file isAbsolutePath] ? file : (self.openedFolderPath ? [self.openedFolderPath stringByAppendingPathComponent:file] : file);
            [parsed addObject:@{
                @"path": absPath,
                @"line": @([lineStr integerValue]),
                @"column": @([colStr integerValue]),
                @"severity": severity,
                @"message": msg
            }];
        }
    }
    return parsed;
}

@end
