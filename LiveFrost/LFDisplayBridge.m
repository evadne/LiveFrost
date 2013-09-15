#import "LFDisplayBridge.h"

void LF_refreshAllSubscribedViewsApplierFunction(const void *value, void *context);

@interface LFDisplayBridge ()
@property (nonatomic, readwrite, assign) CFMutableSetRef subscribedViews;
@property (nonatomic, readonly, strong) CADisplayLink *displayLink;
@property (nonatomic, readonly, strong) dispatch_semaphore_t renderSemaphore;
@property (nonatomic, readonly, strong) dispatch_queue_t renderQueue;
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
		_renderSemaphore = dispatch_semaphore_create(1);
		_renderQueue = dispatch_queue_create(NSStringFromClass(self.class).UTF8String, DISPATCH_QUEUE_SERIAL);
	}
	return self;
}

- (void) addSubscribedViewsObject:(UIView<LFDisplayBridgeTriggering> *)object {
	dispatch_async(_renderQueue, ^{
		CFSetAddValue(_subscribedViews, (__bridge const void*)object);
	});
}

- (void) removeSubscribedViewsObject:(UIView<LFDisplayBridgeTriggering> *)object {
	dispatch_async(_renderQueue, ^{
		CFSetRemoveValue(_subscribedViews, (__bridge const void*)object);
	});
}

- (void) executeBlockOnRenderQueue:(void (^)(void))renderBlock waitUntilDone:(BOOL)wait {
	if (wait) {
		dispatch_sync(_renderQueue, renderBlock);
	} else {
		dispatch_async(_renderQueue, renderBlock);
	}
}

- (void) handleDisplayLink:(CADisplayLink *)displayLink {
	[self refresh];
}

- (void) dealloc {
	[_displayLink invalidate];
	dispatch_sync(_renderQueue, ^{});
	CFRelease(_subscribedViews);
}

- (void) refresh {
	if (dispatch_semaphore_wait(_renderSemaphore, DISPATCH_TIME_NOW) == 0) {
		dispatch_async(_renderQueue, ^{
			CFSetApplyFunction(_subscribedViews, LF_refreshAllSubscribedViewsApplierFunction, NULL);
			dispatch_semaphore_signal(_renderSemaphore);
		});
	}
}

@end
