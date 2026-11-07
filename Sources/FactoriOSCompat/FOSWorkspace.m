#import "FOSAppKit.h"

@import UIKit;

@implementation FOSWorkspace

+ (FOSWorkspace *)sharedWorkspace {
    static FOSWorkspace *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[FOSWorkspace alloc] init];
    });
    return shared;
}

- (void)activateFileViewerSelectingURLs:(NSArray<NSURL *> *)fileURLs {
    NSURL *target = fileURLs.firstObject;
    if (target == nil || !target.isFileURL) {
        return;
    }
    // Files can't select an item; it can open the folder that holds it. The shareddocuments scheme opens a path in
    // the app's container (exposed through UIFileSharingEnabled) in the Files app.
    NSNumber *isDirectory = nil;
    [target getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL];
    NSURL *folder = isDirectory.boolValue ? target : target.URLByDeletingLastPathComponent;
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = @"shareddocuments";
    components.host = @"";
    components.path = folder.path;
    NSURL *filesURL = components.URL;
    if (filesURL == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication.sharedApplication openURL:filesURL options:@{} completionHandler:nil];
    });
}

@end
