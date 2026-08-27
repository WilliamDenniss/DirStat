//
//  LoadingPanelController.m
//  Disk Inventory X
//
//  Created by Tjark Derlien on 03.12.04.
//  Copyright 2004 Tjark Derlien. All rights reserved.
//

#import "LoadingPanelController.h"
#import "LoadingPanelUpdateState.h"
#import "VolumeScanProgress.h"


// NSProgressIndicator has accumulated several animation and layer-backed
// rendering behaviours across macOS releases.  Volume progress must be much
// simpler: one scan-wide value, painted as a persistent fill from the left.
// Keeping the NSProgressIndicator superclass preserves its native
// accessibility role and numeric value while this subclass owns every pixel.
@interface DIXDeterminateProgressIndicator : NSProgressIndicator
@end

@implementation DIXDeterminateProgressIndicator

- (void) setDoubleValue: (double) value
{
	// The view itself enforces the same invariant as the model and controller.
	// Even an accidental stale caller cannot make an already painted bar shrink.
	double currentValue = [super doubleValue];
	value = DIXMonotonicProgressFraction( currentValue, value );
	[super setDoubleValue: value];
	[self setNeedsDisplay: YES];
}

- (void) startAnimation: (id) sender
{
	// A whole-volume progress view never has an animation phase.  Directory
	// changes redraw the label only; the bar remains at its cumulative value.
	// Preserve the public mode-switch API's spinner fallback, though, by using
	// AppKit rendering if this instance is explicitly made indeterminate.
	if ( [self isIndeterminate] )
		[super startAnimation: sender];
}

- (void) drawRect: (NSRect) dirtyRect
{
	if ( [self isIndeterminate] )
	{
		[super drawRect: dirtyRect];
		return;
	}

	NSRect bounds = [self bounds];
	if ( NSIsEmptyRect( bounds ) )
		return;

	CGFloat trackHeight = MIN( 6.0, NSHeight( bounds ) );
	NSRect trackRect = NSMakeRect( NSMinX( bounds ),
								 floor( NSMidY( bounds ) - trackHeight / 2.0 ),
								 NSWidth( bounds ), trackHeight );
	CGFloat radius = trackHeight / 2.0;
	NSBezierPath *track = [NSBezierPath bezierPathWithRoundedRect: trackRect
											 xRadius: radius yRadius: radius];
	[[[NSColor disabledControlTextColor] colorWithAlphaComponent: 0.25] setFill];
	[track fill];

	double range = [self maxValue] - [self minValue];
	double fraction = range <= 0.0 ? 0.0
		: ([self doubleValue] - [self minValue]) / range;
	if ( fraction < 0.0 )
		fraction = 0.0;
	else if ( fraction > 1.0 )
		fraction = 1.0;

	if ( fraction > 0.0 )
	{
		NSRect fillRect = trackRect;
		fillRect.size.width = NSWidth( trackRect ) * fraction;
		if ( [self userInterfaceLayoutDirection] ==
			 NSUserInterfaceLayoutDirectionRightToLeft )
		{
			fillRect.origin.x = NSMaxX( trackRect ) - NSWidth( fillRect );
		}

		NSColor *fillColor = nil;
		if ( @available(macOS 10.14, *) )
			fillColor = [NSColor controlAccentColor];
		else
			fillColor = [NSColor selectedControlColor];

		[NSGraphicsContext saveGraphicsState];
		[track addClip];
		[fillColor setFill];
		NSRectFill( fillRect );
		[NSGraphicsContext restoreGraphicsState];
	}
}

@end


@interface LoadingPanelController (Private)

- (void) initializeProgressIndicatorIndeterminate: (BOOL) indeterminate;
- (void) initializeItemCountTextField;
- (void) replaceProgressIndicatorWithDeterminateIndicatorAtFraction: (double) fraction;
- (void) releaseItemCountTextField;
- (NSTimeInterval) currentUpdateTime;
- (void) flushPendingUpdatesAtTime: (NSTimeInterval) currentTime
						 forceDisplay: (BOOL) forceDisplay;

@end


@implementation LoadingPanelController

- (id) init
{
	return [self initWithIndeterminateProgress: YES];
}

- (id) initWithIndeterminateProgress: (BOOL) indeterminate
{
	self = [super init];
	if ( self == nil )
		return nil;

	_updateState = [[LoadingPanelUpdateState alloc]
					 initWithMinimumUpdateInterval: 0.2];
	
    //load Nib with progress panel
	if ( ![NSBundle loadNibNamed: @"LoadingPanel" owner: self] )
		NSAssert( NO, @"couldn't load LoadingPanel.nib" );
	
	[self initializeItemCountTextField];
	[self initializeProgressIndicatorIndeterminate: indeterminate];

	// LoadingPanel.nib is not visible at launch.  -display only redraws a
	// visible window, so explicitly put the progress panel on screen before
	// starting the modal session.
	[_loadingPanel center];
	[_loadingPanel makeKeyAndOrderFront: self];
	
	//start modal session for the progress window
	_loadingPanelModalSession = [[NSApplication sharedApplication] beginModalSessionForWindow: _loadingPanel];
	_cancelPressed = NO;
	
	return self;
}

- (id) initAsSheetForWindow: (NSWindow*) window
{
	self = [super init];
	if ( self == nil )
		return nil;

	_updateState = [[LoadingPanelUpdateState alloc]
					 initWithMinimumUpdateInterval: 0.2];
	
    //load Nib with progress panel
	if ( ![NSBundle loadNibNamed: @"LoadingPanel" owner: self] )
		NSAssert( NO, @"couldn't load LoadingPanel.nib" );

	[self initializeItemCountTextField];
	[self initializeProgressIndicatorIndeterminate: YES];
	
	[NSApp beginSheet: _loadingPanel
	   modalForWindow: window
		modalDelegate: self
	   didEndSelector: nil
		  contextInfo: NULL];
	
	[_loadingPanel setWorksWhenModal: YES];
	
	//we don't have modal session if we show the panel as a sheet
	_loadingPanelModalSession = 0;
	
	_cancelPressed = NO;
	
	return self;
}

- (void) dealloc
{
	if ( _loadingPanel != nil )
		[self close];

	[_message release];
	[_updateState release];
	
	[super dealloc];
}

- (void) close
{
	if ( [_loadingPanel isSheet] )
	{
		[NSApp endSheet: _loadingPanel];
		[self releaseItemCountTextField];
		[_loadingPanel close]; //will be released (panel has style "release when close")
		
		_loadingPanel = nil;
		_loadingProgressIndicator = nil;
		_loadingTextField = nil;
		_loadingCancelButton = nil;
	}
	else
	{
		OBPRECONDITION( _loadingPanelModalSession != 0 );
		[[NSApplication sharedApplication] endModalSession: _loadingPanelModalSession];
		_loadingPanelModalSession = 0;
		
		[self closeNoModalEnd];
	}
}

- (void) closeNoModalEnd
{
	//this only works if we startet a modal session for a panel (no sheet)
	OBPRECONDITION( ![_loadingPanel isSheet] );
	
	//the sender asked us not to end the modal session (maybe because sender has run into an exception)
	_loadingPanelModalSession = 0;
	[self releaseItemCountTextField];
	
	[_loadingPanel close]; //will be released (panel has style "release when close")
	
	_loadingPanel = nil;
    _loadingProgressIndicator = nil;
	_loadingTextField = nil;
	_loadingCancelButton = nil;
}

- (void) enableCancelButton: (BOOL) enable
{
	[_loadingCancelButton setEnabled: enable];
}

- (BOOL) cancelPressed
{
	return _cancelPressed;
}

- (void) startAnimation;
{
	[_loadingProgressIndicator startAnimation: nil];
}

- (void) stopAnimation;
{
	[_loadingProgressIndicator stopAnimation: nil];
}

- (void) initializeProgressIndicatorIndeterminate: (BOOL) indeterminate
{
	_progressIsIndeterminate = indeterminate;

	if ( indeterminate )
	{
		// Directory traversal is synchronous, so let the indicator animate even
		// while the scanner is between event-loop updates.
		[_loadingProgressIndicator setIndeterminate: YES];
		[_loadingProgressIndicator setUsesThreadedAnimation: YES];
		[_loadingProgressIndicator startAnimation: self];
	}
	else
	{
		// A volume panel must be determinate from its first visible frame.  A
		// progress indicator decoded from the NIB is already a layer-backed,
		// indeterminate control.  Replace it entirely so no serialized marquee
		// animation can survive a property change.
		[self replaceProgressIndicatorWithDeterminateIndicatorAtFraction: 0.0];
		[_loadingProgressIndicator setUsesThreadedAnimation: NO];
		[_loadingProgressIndicator setIndeterminate: NO];
		[_loadingProgressIndicator setDisplayedWhenStopped: YES];
		[_loadingProgressIndicator setMinValue: 0.0];
		[_loadingProgressIndicator setMaxValue: 1.0];
		[_loadingProgressIndicator setDoubleValue: 0.0];
	}

	NSAssert( [_loadingProgressIndicator isIndeterminate] == indeterminate,
			  @"progress indicator mode does not match the requested mode" );
	[_loadingProgressIndicator setNeedsDisplay: YES];
}

- (void) replaceProgressIndicatorWithDeterminateIndicatorAtFraction: (double) fraction
{
	NSProgressIndicator *oldIndicator = _loadingProgressIndicator;
	[oldIndicator stopAnimation: nil];
	NSProgressIndicator *determinateIndicator =
		[[DIXDeterminateProgressIndicator alloc] initWithFrame: [oldIndicator frame]];
	[determinateIndicator setAutoresizingMask: [oldIndicator autoresizingMask]];
	[determinateIndicator setControlSize: [oldIndicator controlSize]];
	[determinateIndicator setStyle: NSProgressIndicatorBarStyle];
	[determinateIndicator setBezeled: [oldIndicator isBezeled]];
	[determinateIndicator setWantsLayer: NO];
	[determinateIndicator setIndeterminate: NO];
	[determinateIndicator setDisplayedWhenStopped: YES];
	[determinateIndicator setMinValue: 0.0];
	[determinateIndicator setMaxValue: 1.0];
	[determinateIndicator setDoubleValue: fraction];
	[determinateIndicator setAccessibilityIdentifier: @"VolumeOverallProgress"];

	[[oldIndicator superview] replaceSubview: oldIndicator with: determinateIndicator];
	_loadingProgressIndicator = determinateIndicator;
	[determinateIndicator release]; //retained by its superview
}

- (void) initializeItemCountTextField
{
	// Reserve a dedicated line for the count so a wrapped absolute path cannot
	// push it out of the fixed-height message field.
	NSRect panelFrame = [_loadingPanel frame];
	panelFrame.size.height += 24.0;
	[_loadingPanel setFrame: panelFrame display: NO];

	NSRect messageFrame = [_loadingTextField frame];
	NSRect progressFrame = [_loadingProgressIndicator frame];
	NSRect countFrame = NSMakeRect( NSMinX( messageFrame ),
									 NSMaxY( progressFrame ) + 5.0,
									 NSWidth( messageFrame ), 17.0 );
	_itemCountTextField = [[NSTextField alloc] initWithFrame: countFrame];
	[_itemCountTextField setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
	[_itemCountTextField setEditable: NO];
	[_itemCountTextField setSelectable: NO];
	[_itemCountTextField setBezeled: NO];
	[_itemCountTextField setDrawsBackground: NO];
	[_itemCountTextField setFont: [_loadingTextField font]];
	[_itemCountTextField setTextColor: [_loadingTextField textColor]];
	[_itemCountTextField setStringValue: @""];
	[[_loadingPanel contentView] addSubview: _itemCountTextField];
}

- (void) releaseItemCountTextField
{
	[_itemCountTextField removeFromSuperview];
	[_itemCountTextField release];
	_itemCountTextField = nil;
}

- (void) setIndeterminate: (BOOL) indeterminate
{
	if ( _progressIsIndeterminate == indeterminate )
		return;

	_progressIsIndeterminate = indeterminate;
	double preservedFraction = DIXMonotonicProgressFraction(
		[_updateState displayedProgressFraction],
		[_updateState pendingProgressFraction] );
	[_updateState queueProgressFraction: preservedFraction];

	if ( indeterminate )
	{
		[_loadingProgressIndicator setIndeterminate: YES];
		[_loadingProgressIndicator setUsesThreadedAnimation: YES];
		[_loadingProgressIndicator startAnimation: self];
	}
	else
	{
		[_loadingProgressIndicator stopAnimation: nil];
		[self replaceProgressIndicatorWithDeterminateIndicatorAtFraction: preservedFraction];
		[_loadingProgressIndicator setUsesThreadedAnimation: NO];
		[_loadingProgressIndicator setIndeterminate: NO];
		[_loadingProgressIndicator setDisplayedWhenStopped: YES];
		[_loadingProgressIndicator setMinValue: 0.0];
		[_loadingProgressIndicator setMaxValue: 1.0];
		[_loadingProgressIndicator setDoubleValue: preservedFraction];
	}

	// Mode changes are infrequent and must be visible before scanning starts.
	NSAssert( [_loadingProgressIndicator isIndeterminate] == indeterminate,
			  @"progress indicator mode does not match the requested mode" );
	[_loadingProgressIndicator setNeedsDisplay: YES];
	[_loadingProgressIndicator displayIfNeeded];
}

- (void) setProgressFraction: (double) fraction
{
	[_updateState queueProgressFraction: fraction];
}

- (void) setMessageText: (NSString*) msg
{
	[msg retain];
	[_message release];
	_message = msg;

	if ( msg != nil )
		[_updateState clearPendingDirectoryUpdate];
}

- (void) setDirectoryURL: (NSURL*) URL itemCount: (unsigned) itemCount
{
	[_message release];
	_message = nil;
	[_updateState queueDirectoryURL: URL itemCount: itemCount];
}

- (void) setDirectoryPath: (NSString*) path itemCount: (unsigned) itemCount
{
	NSURL *URL = path == nil ? nil : [NSURL fileURLWithPath: path];
	[self setDirectoryURL: URL itemCount: itemCount];
}

- (NSTimeInterval) currentUpdateTime
{
	return [[NSProcessInfo processInfo] systemUptime];
}

- (void) flushPendingUpdatesAtTime: (NSTimeInterval) currentTime
						 forceDisplay: (BOOL) forceDisplay

{
	if ( _message != nil )
	{
		[_loadingTextField setStringValue: _message];
		[_itemCountTextField setStringValue: @""];
		[_message release];
		_message = nil;
	}
	else if ( [_updateState hasPendingDirectoryUpdate] )
	{
		NSString *path = [[_updateState pendingDirectoryURL] path];
		NSString *message = [NSString stringWithFormat:
			NSLocalizedString( @"Scanning %@", @"Progress shown while scanning a folder" ),
			path == nil ? @"" : path];
		NSString *countMessage = [NSString stringWithFormat:
			NSLocalizedString( @"%u items found", @"Item count shown while scanning a folder" ),
			[_updateState pendingItemCount]];
		[_loadingTextField setStringValue: message];
		[_itemCountTextField setStringValue: countMessage];
	}

	if ( !_progressIsIndeterminate && [_updateState hasPendingProgressUpdate] )
	{
		[_loadingProgressIndicator setDoubleValue:
			[_updateState pendingProgressFraction]];
		[_loadingProgressIndicator setNeedsDisplay: YES];
	}

	[_updateState noteFlushAtTime: currentTime];

	if ( forceDisplay )
		[_loadingPanel displayIfNeeded];

	// Give the progress dialog some processor cycles.  Ordinary updates reach
	// AppKit only on this tick; there is no per-directory synchronous drawing.
	if ( _loadingPanelModalSession != 0 )
	{
		if ( [[NSApplication sharedApplication] runModalSession: _loadingPanelModalSession]
															!= NSRunContinuesResponse )
		{
			NSAssert( NO, @"run loop stopped by unknown party" );
		}
	}
	else
	{
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate date]];
	}
}

- (void) flushPendingUpdates
{
	NSTimeInterval currentTime = [self currentUpdateTime];
	if ( [_updateState shouldFlushAtTime: currentTime force: YES] )
		[self flushPendingUpdatesAtTime: currentTime forceDisplay: YES];
}

- (void) runEventLoop
{
	// AppKit work is capped at five updates per second.  Calls between ticks
	// merely replace the retained latest values in LoadingPanelUpdateState.
	NSTimeInterval currentTime = [self currentUpdateTime];
	if ( [_updateState shouldFlushAtTime: currentTime force: NO] )
		[self flushPendingUpdatesAtTime: currentTime forceDisplay: NO];
}

- (IBAction) cancel:(id)sender
{
	_cancelPressed = YES;
	
	[_loadingCancelButton setEnabled: NO];
}

@end
