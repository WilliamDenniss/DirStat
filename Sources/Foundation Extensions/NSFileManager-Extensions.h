//
//  NSFileManager-Extensions.h
//  Disk Inventory X
//
//  Created by Doom on 08.11.19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSFileManager(PrivacyProtectedFolders)

// list of folders and files on local volume which are under macOS' privacy protection
- (NSArray<NSURL*>*) localPrivacyProtectedFolders;

// list of folders and files below the specified URL which are under macOS' privacy protection
- (NSArray<NSURL*>*) privacyProtectedFoldersInURL: (NSURL *)url;

// access the protected URLs to trigger macOS' consent dialogs
- (void) triggerConsentDialogForPrivacyProtectedFolders: (NSArray<NSURL*>*) urls;

// access the protected URLs residing below "url" to trigger macOS' consent dialogs
- (void) triggerCosentDialogForPrivacyProtectedFoldersInURL: (NSURL *)url;


@end

NS_ASSUME_NONNULL_END
