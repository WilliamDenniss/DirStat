//
//  LoadingPanelUpdateState.h
//  Disk Inventory X
//

#import <Foundation/Foundation.h>


@interface LoadingPanelUpdateState : NSObject
{
	NSTimeInterval _minimumUpdateInterval;
	NSTimeInterval _lastFlushTime;
	BOOL _hasFlushed;

	NSURL *_pendingDirectoryURL;
	unsigned _pendingItemCount;
	BOOL _hasPendingDirectoryUpdate;

	double _pendingProgressFraction;
	double _displayedProgressFraction;
}

- (id) initWithMinimumUpdateInterval: (NSTimeInterval) interval;

- (void) queueDirectoryURL: (NSURL*) directoryURL itemCount: (unsigned) itemCount;
- (void) clearPendingDirectoryUpdate;
- (BOOL) hasPendingDirectoryUpdate;
- (NSURL*) pendingDirectoryURL;
- (unsigned) pendingItemCount;

- (void) queueProgressFraction: (double) fraction;
- (double) pendingProgressFraction;
- (double) displayedProgressFraction;
- (BOOL) hasPendingProgressUpdate;

// Callers inject their monotonic timestamp so cadence decisions can be tested
// without sleeping or depending on wall-clock time.
- (BOOL) shouldFlushAtTime: (NSTimeInterval) time force: (BOOL) force;
- (void) noteFlushAtTime: (NSTimeInterval) time;

@end
