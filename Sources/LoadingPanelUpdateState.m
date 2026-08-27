//
//  LoadingPanelUpdateState.m
//  Disk Inventory X
//

#import "LoadingPanelUpdateState.h"
#import "VolumeScanProgress.h"


@implementation LoadingPanelUpdateState

- (id) init
{
	return [self initWithMinimumUpdateInterval: 0.2];
}

- (id) initWithMinimumUpdateInterval: (NSTimeInterval) interval
{
	self = [super init];
	if ( self != nil )
	{
		_minimumUpdateInterval = MAX( 0.0, interval );
		_pendingProgressFraction = 0.0;
		_displayedProgressFraction = 0.0;
	}
	return self;
}

- (void) dealloc
{
	[_pendingDirectoryURL release];
	[super dealloc];
}

- (void) queueDirectoryURL: (NSURL*) directoryURL itemCount: (unsigned) itemCount
{
	[directoryURL retain];
	[_pendingDirectoryURL release];
	_pendingDirectoryURL = directoryURL;
	_pendingItemCount = itemCount;
	_hasPendingDirectoryUpdate = YES;
}

- (void) clearPendingDirectoryUpdate
{
	[_pendingDirectoryURL release];
	_pendingDirectoryURL = nil;
	_pendingItemCount = 0;
	_hasPendingDirectoryUpdate = NO;
}

- (BOOL) hasPendingDirectoryUpdate
{
	return _hasPendingDirectoryUpdate;
}

- (NSURL*) pendingDirectoryURL
{
	return _pendingDirectoryURL;
}

- (unsigned) pendingItemCount
{
	return _pendingItemCount;
}

- (void) queueProgressFraction: (double) fraction
{
	double previousFraction = _pendingProgressFraction;
	_pendingProgressFraction = DIXMonotonicProgressFraction(
		_pendingProgressFraction, fraction );
	NSAssert( _pendingProgressFraction >= previousFraction,
			  @"queued progress must never decrease" );
}

- (double) pendingProgressFraction
{
	return _pendingProgressFraction;
}

- (double) displayedProgressFraction
{
	return _displayedProgressFraction;
}

- (BOOL) hasPendingProgressUpdate
{
	return _pendingProgressFraction > _displayedProgressFraction;
}

- (BOOL) shouldFlushAtTime: (NSTimeInterval) time force: (BOOL) force
{
	if ( force || !_hasFlushed )
		return YES;

	// A monotonic clock should not move backwards.  Treat an injected stale
	// timestamp as not due instead of accidentally opening the repaint floodgate.
	if ( time < _lastFlushTime )
		return NO;

	return time - _lastFlushTime >= _minimumUpdateInterval;
}

- (void) noteFlushAtTime: (NSTimeInterval) time
{
	if ( !_hasFlushed || time >= _lastFlushTime )
		_lastFlushTime = time;
	_hasFlushed = YES;

	double previousFraction = _displayedProgressFraction;
	_displayedProgressFraction = DIXMonotonicProgressFraction(
		_displayedProgressFraction, _pendingProgressFraction );
	NSAssert( _displayedProgressFraction >= previousFraction,
			  @"displayed progress must never decrease" );

	[self clearPendingDirectoryUpdate];
}

@end
