#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// One finger's path on the screen: a touch down at the first point, a
/// move to each later point at its time (seconds from the touch down), and
/// a lift at `lift`. Points are in screen points.
@interface ParityPath : NSObject
@property (nonatomic, readonly) NSArray<NSValue *> *points;
@property (nonatomic, readonly) NSArray<NSNumber *> *times;
@property (nonatomic, readonly) NSTimeInterval lift;
- (instancetype)initWithPoints:(NSArray<NSValue *> *)points times:(NSArray<NSNumber *> *)times lift:(NSTimeInterval)lift;
@end

/// Synthesizes touches through XCTest's private `XCPointerEventPath`, the
/// mechanism WebDriverAgent uses: unlike `XCUICoordinate.press(thenDragTo:)`
/// a path can change direction without lifting, can lift a set number of
/// milliseconds after its last move (so the app under test reads a release
/// velocity), and several paths can run at once for a pinch.
@interface ParityTouch : NSObject
+ (BOOL)run:(NSArray<ParityPath *> *)paths error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
