//
//  OAToolbarWindowControllerEx.h
//  Disk Inventory X
//
//  Created by Tjark Derlien on 01.12.04.
//  Copyright 2004 Tjark Derlien. All rights reserved.
//
// Copyright 2026 The DirStat Authors.
// Modified 2026-09-04.

#import <Cocoa/Cocoa.h>
#import "OmniCompatibility.h"

@interface NSToolbarItemValidationAdapter : NSObject
{
	NSToolbarItem* _toolbarItem;
}

- (void) setToolbarItem: (NSToolbarItem*) toolbarItem;
- (void) forwardInvocation: (NSInvocation*) anInvocation;

@end

@interface OAToolbarWindowControllerEx : OAToolbarWindowController {

}

- (NSImage*) toolbar: (NSToolbar*) theToolbar imageForToolbarItem: (NSToolbarItem*) item forState: (int) state;

// properties to resolve "target" value for tool items
@property (readonly) NSDocumentController *documentController;
@property (readonly) NSApplication *application;

@end
