//
//  VolumeScanProgress.m
//  Disk Inventory X
//

#import "VolumeScanProgress.h"

static const double VolumeScanProgressScanningLimit = 0.95;
static const double VolumeScanProgressPrecompletionLimit = 0.999;

double DIXMonotonicProgressFraction(double currentFraction,
                                    double candidateFraction)
{
    // Normalize the stored value defensively. A live progress instance always
    // supplies a finite value in range, but keeping the reducer total makes it
    // safe for every caller and straightforward to test.
    if (currentFraction != currentFraction || currentFraction < 0.0)
        currentFraction = 0.0;
    else if (currentFraction > 1.0)
        currentFraction = 1.0;

    if (candidateFraction != candidateFraction)
        return currentFraction;
    if (candidateFraction < 0.0)
        candidateFraction = 0.0;
    else if (candidateFraction > 1.0)
        candidateFraction = 1.0;

    return candidateFraction > currentFraction
        ? candidateFraction : currentFraction;
}

@interface VolumeScanProgress ()

- (void)setProgressFractionIfGreater:(double)fraction;

@end

@implementation VolumeScanProgress

- (id)initWithTotalCapacity:(NSNumber *)totalCapacity
          availableCapacity:(NSNumber *)availableCapacity
{
    self = [super init];
    if (self != nil)
    {
        _seenFileIdentifiers = [[NSMutableSet alloc] init];

        if (totalCapacity != nil && availableCapacity != nil)
        {
            uint64_t totalBytes = [totalCapacity unsignedLongLongValue];
            uint64_t availableBytes = [availableCapacity unsignedLongLongValue];

            // Comparing both NSNumber values and their converted values also
            // rejects negative and otherwise unrepresentable capacities.
            if ([totalCapacity compare:@0] != NSOrderedAscending
                && [availableCapacity compare:@0] != NSOrderedAscending
                && [totalCapacity compare:availableCapacity] == NSOrderedDescending
                && totalBytes > availableBytes)
            {
                _expectedUsedBytes = totalBytes - availableBytes;
                _determinate = _expectedUsedBytes > 0;
                if (_determinate)
                    _phase = VolumeScanProgressPhaseScanning;
            }
        }
    }
    return self;
}

- (void)dealloc
{
    [_seenFileIdentifiers release];
    [super dealloc];
}

- (BOOL)isDeterminate
{
    return _determinate;
}

- (uint64_t)expectedUsedBytes
{
    return _expectedUsedBytes;
}

- (VolumeScanProgressPhase)phase
{
    return _phase;
}

- (uint64_t)scannedAllocatedBytes
{
    return _scannedAllocatedBytes;
}

- (double)progressFraction
{
    return _progressFraction;
}

- (void)recordAllocatedBytes:(uint64_t)bytes
              fileIdentifier:(id)identifier
                   linkCount:(NSUInteger)linkCount
{
    if (!_determinate || _phase != VolumeScanProgressPhaseScanning)
        return;

    if (linkCount > 1 && identifier != nil)
    {
        if ([_seenFileIdentifiers containsObject:identifier])
            return;

        [_seenFileIdentifiers addObject:identifier];
    }

    if (UINT64_MAX - _scannedAllocatedBytes < bytes)
        _scannedAllocatedBytes = UINT64_MAX;
    else
        _scannedAllocatedBytes += bytes;

    double accountedFraction = (double)_scannedAllocatedBytes / (double)_expectedUsedBytes;
    if (accountedFraction > 1.0)
        accountedFraction = 1.0;

    [self setProgressFractionIfGreater:accountedFraction * VolumeScanProgressScanningLimit];
}

- (void)finishScanning
{
    if (!_determinate || _phase != VolumeScanProgressPhaseScanning)
        return;

    [self setProgressFractionIfGreater:VolumeScanProgressScanningLimit];
}

- (void)beginClassificationWithItemCount:(NSUInteger)itemCount
{
    if (!_determinate || _phase != VolumeScanProgressPhaseScanning)
        return;

    [self finishScanning];
    _phase = VolumeScanProgressPhaseClassification;
    _classificationItemCount = itemCount;
    _classifiedItemCount = 0;
}

- (void)recordClassifiedItem
{
    if (!_determinate || _phase != VolumeScanProgressPhaseClassification
        || _classificationItemCount == 0)
        return;

    if (_classifiedItemCount < _classificationItemCount)
        _classifiedItemCount++;

    double classificationFraction =
        (double)_classifiedItemCount / (double)_classificationItemCount;
    double fraction = VolumeScanProgressScanningLimit
        + classificationFraction * (1.0 - VolumeScanProgressScanningLimit);

    // Successful completion is the only event that may expose exactly 100%.
    if (fraction > VolumeScanProgressPrecompletionLimit)
        fraction = VolumeScanProgressPrecompletionLimit;

    [self setProgressFractionIfGreater:fraction];
}

- (void)finish
{
    if (!_determinate)
        return;

    _phase = VolumeScanProgressPhaseFinished;
    _progressFraction = 1.0;
}

- (void)setProgressFractionIfGreater:(double)fraction
{
    _progressFraction = DIXMonotonicProgressFraction(_progressFraction, fraction);
}

@end
