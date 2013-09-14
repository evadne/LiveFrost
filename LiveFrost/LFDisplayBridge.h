#import <QuartzCore/QuartzCore.h>

@protocol LFDisplayBridgeTriggering <NSObject>
- (void) refresh;
@end

@interface LFDisplayBridge : NSObject <LFDisplayBridgeTriggering>

+ (instancetype) sharedInstance;

@property (nonatomic, readonly, strong) NSMutableSet *subscribedViews;
- (void) addSubscribedViewsObject:(UIView<LFDisplayBridgeTriggering> *)object;
- (void) removeSubscribedViewsObject:(UIView<LFDisplayBridgeTriggering> *)object;

- (void) executeBlockOnRenderQueue:(void (^)(void))renderBlock
                     waitUntilDone:(BOOL)wait;

@end
