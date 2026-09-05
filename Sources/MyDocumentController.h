//
//  MyDocumentController.h
//  Disk Accountant
//
//  Created by Tjark Derlien on Wed Oct 08 2003.
//  Copyright (c) 2003 Tjark Derlien. All rights reserved.
//
//  Copyright 2026 The DirStat Authors.
//  Modified 2026-09-05.

#import <Foundation/Foundation.h>


@interface MyDocumentController : NSDocumentController
{
	IBOutlet NSMenu* _zoomStackMenu;
}

- (IBAction) showPreferencesPanel: (id) sender;
- (IBAction) openDocumentation: (id) sender;

- (void) openDocumentWithContentsOfFile: (NSString*) fileName; //calls "openDocumentWithContentsOfFile: fileName display: [self shouldCreateUI]"
@end
