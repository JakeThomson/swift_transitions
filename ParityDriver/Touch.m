#import "Touch.h"
#import <XCTest/XCTest.h>
#import <objc/message.h>

@implementation ParityPath
- (instancetype)initWithPoints:(NSArray<NSValue *> *)points times:(NSArray<NSNumber *> *)times lift:(NSTimeInterval)lift {
    self = [super init];
    if (self) {
        _points = points;
        _times = times;
        _lift = lift;
    }
    return self;
}
@end

@implementation ParityTouch

+ (BOOL)run:(NSArray<ParityPath *> *)paths error:(NSError **)error {
    Class pathClass = NSClassFromString(@"XCPointerEventPath");
    Class recordClass = NSClassFromString(@"XCSynthesizedEventRecord");
    if (pathClass == nil || recordClass == nil) {
        if (error) {
            *error = [NSError errorWithDomain:@"ParityTouch" code:1 userInfo:@{NSLocalizedDescriptionKey: @"XCPointerEventPath is not in this XCTest"}];
        }
        return NO;
    }
    id record = ((id (*)(id, SEL, id, NSInteger))objc_msgSend)(
        [recordClass alloc], NSSelectorFromString(@"initWithName:interfaceOrientation:"), @"parity", 1);
    for (ParityPath *path in paths) {
        CGPoint first = path.points.firstObject.CGPointValue;
        id eventPath = ((id (*)(id, SEL, CGPoint, NSTimeInterval))objc_msgSend)(
            [pathClass alloc], NSSelectorFromString(@"initForTouchAtPoint:offset:"), first, path.times.firstObject.doubleValue);
        for (NSUInteger i = 1; i < path.points.count; i++) {
            ((void (*)(id, SEL, CGPoint, NSTimeInterval))objc_msgSend)(
                eventPath, NSSelectorFromString(@"moveToPoint:atOffset:"), path.points[i].CGPointValue, path.times[i].doubleValue);
        }
        ((void (*)(id, SEL, NSTimeInterval))objc_msgSend)(eventPath, NSSelectorFromString(@"liftUpAtOffset:"), path.lift);
        ((void (*)(id, SEL, id))objc_msgSend)(record, NSSelectorFromString(@"addPointerEventPath:"), eventPath);
    }
    NSDate *started = [NSDate date];
    __block NSError *failure = nil;
    __block BOOL finished = NO;
    id synthesizer = ((id (*)(id, SEL))objc_msgSend)([XCUIDevice sharedDevice], NSSelectorFromString(@"eventSynthesizer"));
    // The completion is `(BOOL succeeded, NSError *error)` since Xcode 12.
    ((void (*)(id, SEL, id, id))objc_msgSend)(
        synthesizer, NSSelectorFromString(@"synthesizeEvent:completion:"), record, ^(BOOL succeeded, NSError *invokeError) {
            failure = succeeded ? nil : (invokeError ?: [NSError errorWithDomain:@"ParityTouch" code:3 userInfo:@{NSLocalizedDescriptionKey: @"synthesis failed"}]);
            finished = YES;
        });
    // Spin the main run loop rather than block it: the synthesizer paces
    // the events from here.
    while (!finished) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    NSLog(@"ParityTouch: %lu paths, %.2fs of events, took %.2fs (%@)", (unsigned long)paths.count,
          ((double (*)(id, SEL))objc_msgSend)(record, NSSelectorFromString(@"maximumOffset")), -started.timeIntervalSinceNow, failure ?: @"ok");
    if (failure != nil && error) {
        *error = failure;
    }
    return failure == nil;
}

@end

