//
//  LoadingPanelController.h
//  Disk Inventory X
//
//  Created by Tjark Derlien on 03.12.04.
//  Copyright 2004 Tjark Derlien. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface LoadingPanelController : NSObject
{
	NSModalSession _loadingPanelModalSession;
	uint64_t _lastEventLoopRun;
	BOOL _cancelPressed;
	NSString *_message;
	NSString *_itemCountMessage;
	BOOL _progressIsIndeterminate;
	double _pendingProgressFraction;
	double _displayedProgressFraction;
    IBOutlet NSTextField* _loadingTextField;
	NSTextField *_itemCountTextField;
    IBOutlet NSPanel* _loadingPanel;
    IBOutlet NSProgressIndicator* _loadingProgressIndicator;
    IBOutlet NSButton* _loadingCancelButton;
}

- (id) init; //will start modal session immediately
- (id) initWithIndeterminateProgress: (BOOL) indeterminate; //will start modal session immediately
- (id) initAsSheetForWindow: (NSWindow*) window; //will start modal session immediately

- (void) close;
- (void) closeNoModalEnd;

- (void) enableCancelButton: (BOOL) enable; //button is enabled by default
- (BOOL) cancelPressed;

- (void) startAnimation;
- (void) stopAnimation;

- (void) setIndeterminate: (BOOL) indeterminate;
- (void) setProgressFraction: (double) fraction;

- (void) setMessageText: (NSString*) msg; //message will be shown next time "runEventLoop" is called
- (void) setDirectoryPath: (NSString*) path itemCount: (unsigned) itemCount;
- (void) runEventLoop;

- (IBAction) cancel:(id)sender;

@end
