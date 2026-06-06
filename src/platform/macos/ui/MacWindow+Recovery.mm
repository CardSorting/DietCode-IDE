#import "MacWindow+Private.hpp"
#import "MacWindowUtilities.hpp"
#import "MacEditorComponents.hpp"

using namespace dietcode::platform::macos;

@implementation DietCodeWindowController (Recovery)

- (NSString*)getBackupDirectory {
    NSString* home = NSHomeDirectory();
    NSString* dir = [home stringByAppendingPathComponent:@".dietcode/backups"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

- (void)saveBackupForTab:(DietCodeTabState*)tab {
    if (!tab.dirty) return;
    
    NSString* backupDir = [self getBackupDirectory];
    NSString* key = tab.path ? tab.path : [NSString stringWithFormat:@"Untitled-%p", tab];
    NSString* safeKey = [[key dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    safeKey = [safeKey stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString* backupPath = [backupDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.bak", safeKey]];
    
    NSString* originalPathStr = tab.path ? tab.path : @"[Untitled]";
    NSString* titleStr = tab.title;
    NSString* text = [tab.textView string];
    
    NSString* backupContent = [NSString stringWithFormat:@"%@\n%@\n%@", originalPathStr, titleStr, text];
    
    NSError* error = nil;
    [backupContent writeToFile:backupPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
}

- (void)deleteBackupForTab:(DietCodeTabState*)tab {
    NSString* backupDir = [self getBackupDirectory];
    NSString* key = tab.path ? tab.path : [NSString stringWithFormat:@"Untitled-%p", tab];
    NSString* safeKey = [[key dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    safeKey = [safeKey stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString* backupPath = [backupDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.bak", safeKey]];
    
    [[NSFileManager defaultManager] removeItemAtPath:backupPath error:nil];
}

- (void)checkForRecoverableFiles {
    if (self.isHeadless) return;
    NSString* backupDir = [self getBackupDirectory];
    NSArray* files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:backupDir error:nil];
    NSMutableArray* backups = [NSMutableArray array];
    
    for (NSString* file in files) {
        if ([file hasSuffix:@".bak"]) {
            NSString* path = [backupDir stringByAppendingPathComponent:file];
            [backups addObject:path];
        }
    }
    
    if (backups.count == 0) return;
    [self showRecoveryDialogWithBackups:backups];
}

- (void)showRecoveryDialogWithBackups:(NSArray<NSString*>*)backupPaths {
    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Unclean Shutdown Detected"];
    [alert setInformativeText:@"DietCode closed unexpectedly. Unsaved work was found. Would you like to restore or discard these files?"];
    [alert addButtonWithTitle:@"Restore"];
    [alert addButtonWithTitle:@"Discard"];
    
    NSStackView* stack = [[NSStackView alloc] init];
    [stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [stack setAlignment:NSLayoutAttributeLeading];
    [stack setSpacing:4];
    
    for (NSString* backupPath in backupPaths) {
        NSString* content = [NSString stringWithContentsOfFile:backupPath encoding:NSUTF8StringEncoding error:nil];
        if (!content) continue;
        
        NSArray* lines = [content componentsSeparatedByString:@"\n"];
        if (lines.count < 2) continue;
        
        NSString* originalPath = lines[0];
        NSString* title = lines[1];
        
        NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:backupPath error:nil];
        NSDate* modDate = attrs.fileModificationDate;
        NSDateFormatter* df = [[NSDateFormatter alloc] init];
        [df setDateStyle:NSDateFormatterShortStyle];
        [df setTimeStyle:NSDateFormatterShortStyle];
        
        NSString* labelText = [NSString stringWithFormat:@"• %@ (%@) — Saved: %@", title, originalPath, [df stringFromDate:modDate]];
        NSTextField* label = MakeLabel(labelText, 11, NSFontWeightRegular);
        [stack addArrangedSubview:label];
    }
    
    [alert setAccessoryView:stack];
    [alert setAlertStyle:NSAlertStyleWarning];
    
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        for (NSString* backupPath in backupPaths) {
            NSString* content = [NSString stringWithContentsOfFile:backupPath encoding:NSUTF8StringEncoding error:nil];
            if (!content) continue;
            
            NSArray* lines = [content componentsSeparatedByString:@"\n"];
            if (lines.count >= 3) {
                NSString* originalPath = lines[0];
                NSString* fileContent = [[lines subarrayWithRange:NSMakeRange(2, lines.count - 2)] componentsJoinedByString:@"\n"];
                NSString* pathVal = [originalPath isEqualToString:@"[Untitled]"] ? nil : originalPath;
                [self showEditorWithText:fileContent path:pathVal dirty:YES];
            }
            [[NSFileManager defaultManager] removeItemAtPath:backupPath error:nil];
        }
    } else {
        for (NSString* backupPath in backupPaths) {
            [[NSFileManager defaultManager] removeItemAtPath:backupPath error:nil];
        }
    }
}

- (void)checkExternalStatusForTab:(DietCodeTabState*)tab {
    if (tab.path == nil || tab.isDiff) return;
    
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:tab.path isDirectory:&isDir]) {
        if (self.isHeadless) {
            tab.path = nil;
            tab.title = [NSString stringWithFormat:@"%@ (Deleted)", tab.title];
            tab.dirty = YES;
            [self updateTabHeaderLayout];
            [self updateWindowTitleAndStatus];
            return;
        }
        NSAlert* alert = [[NSAlert alloc] init];
        [alert setMessageText:@"File Deleted Externally"];
        [alert setInformativeText:[NSString stringWithFormat:@"The file '%@' has been deleted externally. Would you like to keep the editor open or close it?", tab.title]];
        [alert addButtonWithTitle:@"Keep Open"];
        [alert addButtonWithTitle:@"Close Tab"];
        [alert setAlertStyle:NSAlertStyleWarning];
        
        NSModalResponse res = [alert runModal];
        if (res == NSAlertSecondButtonReturn) {
            tab.dirty = NO;
            [self closeTab:tab];
        } else {
            tab.path = nil;
            tab.title = [NSString stringWithFormat:@"%@ (Deleted)", tab.title];
            tab.dirty = YES;
            [self updateTabHeaderLayout];
            [self updateWindowTitleAndStatus];
        }
        return;
    }
    
    NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:tab.path error:nil];
    NSDate* diskModDate = attrs.fileModificationDate;
    if (tab.lastModifiedDate && [diskModDate compare:tab.lastModifiedDate] == NSOrderedDescending) {
        if (self.isHeadless) {
            const auto result = fileService_.readTextFile(std::filesystem::path(StdStringFromNSString(tab.path)));
            if (result.ok) {
                self.loadingDocument = YES;
                [tab.textView setString:NSStringFromStdString(result.contents)];
                self.loadingDocument = NO;
                tab.dirty = NO;
                tab.lastModifiedDate = diskModDate;
                [self updateTabHeaderLayout];
                [self updateWindowTitleAndStatus];
            }
            return;
        }
        NSAlert* alert = [[NSAlert alloc] init];
        [alert setMessageText:@"File Modified Externally"];
        [alert setInformativeText:[NSString stringWithFormat:@"The file '%@' has been modified by another program. Do you want to reload it and discard your local edits?", tab.title]];
        [alert addButtonWithTitle:@"Reload File"];
        [alert addButtonWithTitle:@"Ignore"];
        [alert setAlertStyle:NSAlertStyleWarning];
        
        NSModalResponse res = [alert runModal];
        if (res == NSAlertFirstButtonReturn) {
            const auto result = fileService_.readTextFile(std::filesystem::path(StdStringFromNSString(tab.path)));
            if (result.ok) {
                self.loadingDocument = YES;
                [tab.textView setString:NSStringFromStdString(result.contents)];
                self.loadingDocument = NO;
                tab.dirty = NO;
                tab.lastModifiedDate = diskModDate;
                [self updateTabHeaderLayout];
                [self updateWindowTitleAndStatus];
            }
        } else {
            tab.lastModifiedDate = diskModDate;
        }
    }
}

@end
