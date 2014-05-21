//
// Copyright (c) 2013-2014 Evadne Wu and Nicholas Levin
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#import "LFGlassView.h"
#import "LFGlassLayer.h"
#import "LFDisplayBridge.h"

@interface LFGlassView ()

@property (nonatomic, assign, readonly) BOOL shouldLiveBlur;

@property (nonatomic, assign, readonly) BOOL blurOnceIfPossible;
@property (nonatomic, strong, readonly) NSSet *methodNamesToForwardToLayer;

- (void) setup;
- (void) handleBlurringOnBoundsChange;

@end

#if !__has_feature(objc_arc)
#error This implementation file must be compiled with Objective-C ARC.

#error Compile this file with the -fobjc-arc flag under your target's Build Phases,
#error   or convert your project to Objective-C ARC.
#endif

@implementation LFGlassView
@dynamic blurRadius;
@dynamic scaleFactor;
@dynamic frameInterval;
@dynamic liveBlurring;
@dynamic blurOnceIfPossible;

+ (Class) layerClass {
	return [LFGlassLayer class];
}

- (id) initWithFrame:(CGRect)frame {
	if (self = [super initWithFrame:frame]) {
		[self setup];
	}
	return self;
}

- (id) initWithCoder:(NSCoder *)aDecoder {
	if (self = [super initWithCoder:aDecoder]) {
		[self setup];
	}
	return self;
}

- (void) setup {
	_glassLayer = (LFGlassLayer*)self.layer;
	self.clipsToBounds = YES;
	self.userInteractionEnabled = NO;
	_shouldLiveBlur = YES;
	_methodNamesToForwardToLayer = [NSSet setWithObjects:@"blurRadius", @"setBlurRadius:", @"scaleFactor", @"setScaleFactor:", @"frameInterval", @"setFrameInterval:", @"blurOnceIfPossible", nil];
}

- (void) dealloc {
	[self stopLiveBlurring];
}

- (void) setBounds:(CGRect)bounds {
	[super setBounds:bounds];
	[self handleBlurringOnBoundsChange];
}

- (void) setFrame:(CGRect)frame {
	[super setFrame:frame];
	[self handleBlurringOnBoundsChange];
}

- (void) handleBlurringOnBoundsChange {
	if (CGRectIsEmpty(self.bounds)) {
		[self stopLiveBlurring];
	} else {
		[self startLiveBlurringIfReady];
	}
}

- (void) didMoveToSuperview {
	[super didMoveToSuperview];
	[self startLiveBlurringIfReady];
}

- (void) didMoveToWindow {
	[super didMoveToWindow];
	if (self.window) {
		[self startLiveBlurringIfReady];
	} else {
		[self stopLiveBlurring];
	}
}

- (BOOL) isLiveBlurring {
	return _shouldLiveBlur;
}

- (void) setLiveBlurring:(BOOL)liveBlurring {
	if (liveBlurring == _shouldLiveBlur) {
		return;
	}
	
	if (liveBlurring) {
		_shouldLiveBlur = YES;
		[self startLiveBlurringIfReady];
	} else {
		_shouldLiveBlur = NO;
		[self stopLiveBlurring];
	}
}

- (void) startLiveBlurringIfReady {
	if ([self isReadyToLiveBlur]) {
		[self blurOnceIfPossible];
		[[LFDisplayBridge sharedInstance] addSubscribedObject:_glassLayer];
	}
}

- (void) stopLiveBlurring {
	[[LFDisplayBridge sharedInstance] removeSubscribedObject:_glassLayer];
}

- (BOOL) isReadyToLiveBlur {
	return (!CGRectIsEmpty(self.bounds) && self.superview && self.window && _shouldLiveBlur);
}

- (NSMethodSignature *) methodSignatureForSelector:(SEL)aSelector {
	if ([_methodNamesToForwardToLayer containsObject:NSStringFromSelector(aSelector)]) {
		return [[self.glassLayer class] instanceMethodSignatureForSelector:aSelector];
	}
	return [super methodSignatureForSelector:aSelector];
}

- (void) forwardInvocation:(NSInvocation *)anInvocation {
	if ([self.glassLayer respondsToSelector:[anInvocation selector]]) {
		[anInvocation invokeWithTarget:self.glassLayer];
	} else {
		[super forwardInvocation:anInvocation];
	}
}

- (id<CAAction>) actionForLayer:(CALayer *)layer forKey:(NSString *)event {
	if ([event isEqualToString:@"blurRadius"] && self.blurRadiusAnimationEnabled) {
		return nil;
	}
	return [super actionForLayer:layer forKey:event];
}

@end
