#import <Accelerate/Accelerate.h>
#import <QuartzCore/QuartzCore.h>

@interface LFGlassView : UIView

@property (nonatomic, assign) CGFloat blurRadius;
@property (nonatomic, assign) CGFloat scaleFactor;

@property (nonatomic, assign, getter=isLiveBlurring) BOOL liveBlurring;

@property (nonatomic, assign) uint_fast32_t frameInterval;

@end
