//
//  VolumeScanProgress.h
//  Disk Inventory X
//

#import <Foundation/Foundation.h>

// Shared by the scan tracker and the loading panel so stale or throttled UI
// samples can never replace a fraction that has already been observed.
FOUNDATION_EXPORT double DIXMonotonicProgressFraction(double currentFraction,
                                                       double candidateFraction);
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, VolumeScanProgressPhase)
{
    VolumeScanProgressPhaseDisabled,
    VolumeScanProgressPhaseScanning,
    VolumeScanProgressPhaseClassification,
    VolumeScanProgressPhaseFinished
};

@interface VolumeScanProgress : NSObject
{
    BOOL _determinate;
    VolumeScanProgressPhase _phase;
    uint64_t _expectedUsedBytes;
    uint64_t _scannedAllocatedBytes;
    double _progressFraction;
    NSMutableSet *_seenFileIdentifiers;
    NSUInteger _classificationItemCount;
    NSUInteger _classifiedItemCount;
}

- (id)initWithTotalCapacity:(nullable NSNumber *)totalCapacity
          availableCapacity:(nullable NSNumber *)availableCapacity;

@property(nonatomic, readonly, getter=isDeterminate) BOOL determinate;
@property(nonatomic, readonly) VolumeScanProgressPhase phase;
@property(nonatomic, readonly) uint64_t expectedUsedBytes;
@property(nonatomic, readonly) uint64_t scannedAllocatedBytes;
@property(nonatomic, readonly) double progressFraction;

- (void)recordAllocatedBytes:(uint64_t)bytes
              fileIdentifier:(nullable id)identifier
                   linkCount:(NSUInteger)linkCount;
- (void)finishScanning;
- (void)beginClassificationWithItemCount:(NSUInteger)itemCount;
- (void)recordClassifiedItem;
- (void)finish;

@end

NS_ASSUME_NONNULL_END
