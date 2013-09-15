#import "LFDisplayBridge.h"

void LF_refreshAllSubscribedViewsApplierFunction(const void *value, void *context);

@interface LFDisplayBridge ()

@property (nonatomic, readwrite, assign) CFMutableSetRef subscribedViews;
@property (nonatomic, readonly, strong) CADisplayLink *displayLink;

@end

void LF_refreshAllSubscribedViewsApplierFunction(const void *value, void *context) {
	[(__bridge UIView<LFDisplayBridgeTriggering> *)value refresh];
}

@implementation LFDisplayBridge

+ (instancetype) sharedInstance {
	static dispatch_once_t onceToken;
	static LFDisplayBridge *object = nil;
	dispatch_once(&onceToken, ^{
		object = [self new];
	});
	return object;
}

- (id) init {
	if (self = [super init]) {
		_subscribedViews = CFSetCreateMutable(kCFAllocatorDefault, 0, NULL);
		_displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(handleDisplayLink:)];
		[_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
	}
	return self;
}

- (void) addSubscribedViewsObject:(UIView<LFDisplayBridgeTriggering> *)object {
	CFSetAddValue(_subscribedViews, (__bridge const void*)object);
}

- (void) removeSubscribedViewsObject:(UIView<LFDisplayBridgeTriggering> *)object {
	CFSetRemoveValue(_subscribedViews, (__bridge const void*)object);
}

- (void) handleDisplayLink:(CADisplayLink *)displayLink {
	[self refresh];
}

- (void) dealloc {
	[_displayLink invalidate];
	CFRelease(_subscribedViews);
}

- (void) refresh {
	CFSetApplyFunction(_subscribedViews, LF_refreshAllSubscribedViewsApplierFunction, NULL);
}

@end
