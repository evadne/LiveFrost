#import <QuartzCore/QuartzCore.h>

@protocol LFDisplayBridgeTriggering <NSObject>
- (void) refresh;
@end

@interface LFDisplayBridge : NSObject <LFDisplayBridgeTriggering>

+ (instancetype) sharedInstance;

@property (nonatomic, readonly, assign) CFMutableSetRef subscribedViews;
- (void) addSubscribedViewsObject:(UIView<LFDisplayBridgeTriggering> *)object;
- (void) removeSubscribedViewsObject:(UIView<LFDisplayBridgeTriggering> *)object;

@end
