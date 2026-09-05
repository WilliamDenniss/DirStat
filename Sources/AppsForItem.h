//
//  AppsForItem.h
//  Disk Inventory X new
//
//  Created by Tjark Derlien on 20.01.06.
//  Copyright 2006 Tjark Derlien. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface AppsForItem : NSObject {
	NSURL *_defaultAppURL;
	NSMutableArray<NSURL*> *_additionalAppURLs;
	NSURL *_itemURL; //file/folder for which to search for applications
}

+ (id) appsForItemURL: (NSURL*) url;
- (id) initWithItemURL: (NSURL*) url;

- (NSURL*) defaultAppURL; //may return nil
- (NSArray<NSURL*>*) additionalAppURLs; //may return empty array (but never nil)

- (NSURL*) itemURL;

- (void) openItemWithAppURL: (NSURL*) appDesc;
+ (void) openItemURL: (NSURL*) item withAppURL: (NSURL*) appDesc;

@end
