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

#import "LFGlassLayer.h"
#import "LFDefines.h"

@interface LFGlassLayer ()

@property (nonatomic, assign, readonly) CGSize cachedBufferSize;
@property (nonatomic, assign, readonly) CGSize scaledSize;

@property (nonatomic, assign, readonly) CGContextRef effectInContext;
@property (nonatomic, assign, readonly) CGContextRef effectOutContext;

@property (nonatomic, assign, readonly) vImage_Buffer effectInBuffer;
@property (nonatomic, assign, readonly) vImage_Buffer effectOutBuffer;

@property (nonatomic, assign, readonly) uint32_t precalculatedBlurKernel;

@property (nonatomic, assign, readonly) NSUInteger currentFrameInterval;

@property (nonatomic, strong, readonly) CALayer *backgroundColorLayer;

@property (nonatomic, assign, readonly) void *blurRadiusObserverContext;

- (void) setup;
- (void) updatePrecalculatedBlurKernel;
- (void) adjustLayerAndImageBuffersFromFrame:(CGRect)fromFrame;
- (CGRect) visibleBoundsToBlur;
- (void) recalculateFrame;
- (CGRect) visibleFrameToBlur;
- (void) recreateImageBuffers;
- (void) forceRefresh;

@end

#if !__has_feature(objc_arc)
#error This implementation file must be compiled with Objective-C ARC.

#error Compile this file with the -fobjc-arc flag under your target's Build Phases,
#error	 or convert your project to Objective-C ARC.
#endif

void *LFGlassLayerBlurRadiusObserverContext = &LFGlassLayerBlurRadiusObserverContext;

@implementation LFGlassLayer
@dynamic blurRadius;
@dynamic scaledSize;

- (id) init {
	if (self = [super init]) {
		[self setup];
	}
	return self;
}

- (id) initWithLayer:(id)layer {
	if (self = [super initWithLayer:layer]) {
#ifdef DEBUG
		NSParameterAssert([layer isKindOfClass:[LFGlassLayer class]]);
#endif
		LFGlassLayer *originalLayer = (LFGlassLayer*)layer;
		[CATransaction begin];
		[CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
		self.blurRadius = originalLayer.blurRadius;
		[CATransaction commit];
		_scaleFactor = originalLayer.scaleFactor;
		_frameInterval = originalLayer.frameInterval;
		_customBlurTargetLayer = originalLayer.customBlurTargetLayer;
		_customBlurBounds = originalLayer.customBlurBounds;
		_customBlurPosition = originalLayer.customBlurPosition;
		_customBlurAnchorPoint = originalLayer.customBlurAnchorPoint;
		_customBlurFrame = originalLayer.customBlurFrame;
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
	[self addObserver:self
	       forKeyPath:@"blurRadius"
	          options:0
	          context:LFGlassLayerBlurRadiusObserverContext];
	_blurRadiusObserverContext = LFGlassLayerBlurRadiusObserverContext;
	
	[CATransaction begin];
	[CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
	self.blurRadius = 4.0f;
	[CATransaction commit];
	
	_backgroundColorLayer = [CALayer layer];
	_backgroundColorLayer.actions = @{
		@"bounds": [NSNull null],
		@"position": [NSNull null]
	};
	self.backgroundColor = [[UIColor clearColor] CGColor];
	self.scaleFactor = 0.25f;
	self.opaque = NO;
	self.actions = @{
		@"contents": [NSNull null],
		@"hidden": [NSNull null]
	};
	_frameInterval = 1;
	_currentFrameInterval = 0;
	[self resetCustomPositioning];
}

- (void) dealloc {
	if (_blurRadiusObserverContext) {
		[self removeObserver:self
		          forKeyPath:@"blurRadius"
		             context:LFGlassLayerBlurRadiusObserverContext];
	}
	
	if (_effectInContext) {
		CGContextRelease(_effectInContext);
	}
	if (_effectOutContext) {
		CGContextRelease(_effectOutContext);
	}
}

- (void) updatePrecalculatedBlurKernel {
	uint32_t radius = (uint32_t)floor(self.blurRadius * 3. * sqrt(2 * M_PI) / 4 + 0.5);
	radius += (radius + 1) % 2;
	_precalculatedBlurKernel = radius;
}

- (void) setBackgroundColor:(CGColorRef)backgroundColor {
	[super setBackgroundColor:backgroundColor];
	
	_backgroundColorLayer.backgroundColor = backgroundColor;
	
	if (CGColorGetAlpha(backgroundColor)) {
		[self insertSublayer:self.backgroundColorLayer atIndex:0];
	} else {
		[self.backgroundColorLayer removeFromSuperlayer];
	}
}

- (void) setBounds:(CGRect)bounds {
	CGRect oldFrame = [self visibleFrameToBlur];
	[super setBounds:bounds];
	[self adjustLayerAndImageBuffersFromFrame:oldFrame];
}

- (void) setPosition:(CGPoint)position {
	CGRect oldFrame = [self visibleFrameToBlur];
	[super setPosition:position];
	[self adjustLayerAndImageBuffersFromFrame:oldFrame];
}

- (void) setAnchorPoint:(CGPoint)anchorPoint {
	CGRect oldFrame = [self visibleFrameToBlur];
	[super setAnchorPoint:anchorPoint];
	[self adjustLayerAndImageBuffersFromFrame:oldFrame];
}

- (void) adjustLayerAndImageBuffersFromFrame:(CGRect)fromFrame {
	if (CGRectEqualToRect(fromFrame, [self visibleFrameToBlur])) {
		return;
	}
	
	_backgroundColorLayer.frame = self.bounds;
	
	if (!CGRectIsEmpty(self.bounds)) {
		[self recreateImageBuffers];
	}
}

- (void) setScaleFactor:(CGFloat)scaleFactor {
	_scaleFactor = scaleFactor;
	CGSize scaledSize = self.scaledSize;
	if (!CGSizeEqualToSize(_cachedBufferSize, scaledSize)) {
		_cachedBufferSize = scaledSize;
		[self recreateImageBuffers];
	}
}

- (CGSize) scaledSize {
	CGRect visibleBounds = [self visibleBoundsToBlur];
	CGSize scaledSize = (CGSize){
		_scaleFactor * CGRectGetWidth(visibleBounds),
		_scaleFactor * CGRectGetHeight(visibleBounds)
	};
	return scaledSize;
}

- (void) setFrameInterval:(NSUInteger)frameInterval {
	if (frameInterval == _frameInterval) {
		return;
	}
	if (frameInterval == 0) {
		NSLog(@"warning: attempted to set frameInterval to 0; frameInterval must be 1 or greater");
		return;
	}
	
	_frameInterval = frameInterval;
}

- (BOOL) blurOnceIfPossible {
	if (!CGRectIsEmpty(self.bounds) && self.presentationLayer) {
		[self forceRefresh];
		return YES;
	} else {
		return NO;
	}
}

- (void) setCustomBlurBounds:(CGRect)blurBounds {
	_customBlurBounds = blurBounds;
	[self recalculateFrame];
}

- (void) setCustomBlurAnchorPoint:(CGPoint)blurAnchorPoint {
	_customBlurAnchorPoint = blurAnchorPoint;
	[self recalculateFrame];
}

- (void) setCustomBlurPosition:(CGPoint)blurPosition {
	_customBlurPosition = blurPosition;
	[self recalculateFrame];
}

- (void) setCustomBlurFrame:(CGRect)blurFrame {
	CGRect newBlurBounds = (CGRect){ CGPointZero, blurFrame.size };
	_customBlurBounds = newBlurBounds;
	
	_customBlurAnchorPoint = (CGPoint){ 0.5, 0.5 };
	
	_customBlurPosition = (CGPoint){
		blurFrame.origin.x + 0.5 * CGRectGetWidth(newBlurBounds),
		blurFrame.origin.y + 0.5 * CGRectGetHeight(newBlurBounds)
	};
	
	_customBlurFrame = blurFrame;
}

- (void) resetCustomPositioning {
	_customBlurBounds = CGRectNull;
	_customBlurAnchorPoint = LFPointNull;
	_customBlurPosition = LFPointNull;
	_customBlurFrame = CGRectNull;
}

- (CGRect) visibleBoundsToBlur {
	return CGRectEqualToRect(_customBlurBounds, CGRectNull) ? self.bounds : _customBlurBounds;
}

- (CGPoint) visibleAnchorPointToBlur {
	return CGPointEqualToPoint(_customBlurAnchorPoint, LFPointNull) ? self.anchorPoint : _customBlurAnchorPoint;
}

- (CGPoint) visiblePositionToBlur {
	return CGPointEqualToPoint(_customBlurPosition, LFPointNull) ? self.position : _customBlurPosition;
}

- (void) recalculateFrame {
	CGRect bounds = [self visibleBoundsToBlur];
	CGPoint anchorPoint = [self visibleAnchorPointToBlur];
	CGPoint position = [self visiblePositionToBlur];

	_customBlurFrame = (CGRect){
		-bounds.size.width * anchorPoint.x + position.x,
		-bounds.size.height * anchorPoint.y + position.y,
		bounds.size.width,
		bounds.size.height
	};
}

- (CGRect) visibleFrameToBlur {
	return CGRectEqualToRect(_customBlurFrame, CGRectNull) ? self.frame : _customBlurFrame;
}

- (void) recreateImageBuffers {
	CGRect visibleRect = [self visibleFrameToBlur];
	CGSize bufferSize = self.scaledSize;
	if (bufferSize.width == 0.0 || bufferSize.height == 0.0) {
		return;
	}
	
	size_t bufferWidth = (size_t)rint(bufferSize.width);
	size_t bufferHeight = (size_t)rint(bufferSize.height);
	if (bufferWidth == 0) {
		bufferWidth = 1;
	}
	if (bufferHeight == 0) {
		bufferHeight = 1;
	}
	
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	
	CGContextRef effectInContext = CGBitmapContextCreate(NULL, bufferWidth, bufferHeight, 8, bufferWidth * 8, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	
	CGContextRef effectOutContext = CGBitmapContextCreate(NULL, bufferWidth, bufferHeight, 8, bufferWidth * 8, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	
	CGColorSpaceRelease(colorSpace);
	
	CGContextConcatCTM(effectInContext, (CGAffineTransform){
		1.0, 0.0, 0.0, -1.0, 0.0, bufferSize.height
	});
	CGContextScaleCTM(effectInContext, _scaleFactor, _scaleFactor);
	CGContextTranslateCTM(effectInContext, -visibleRect.origin.x, -visibleRect.origin.y);
	
	if (_effectInContext) {
		CGContextRelease(_effectInContext);
	}
	_effectInContext = effectInContext;
	
	if (_effectOutContext) {
		CGContextRelease(_effectOutContext);
	}
	_effectOutContext = effectOutContext;
	
	_effectInBuffer = (vImage_Buffer){
		.data = CGBitmapContextGetData(effectInContext),
		.width = CGBitmapContextGetWidth(effectInContext),
		.height = CGBitmapContextGetHeight(effectInContext),
		.rowBytes = CGBitmapContextGetBytesPerRow(effectInContext)
	};
	
	_effectOutBuffer = (vImage_Buffer){
		.data = CGBitmapContextGetData(effectOutContext),
		.width = CGBitmapContextGetWidth(effectOutContext),
		.height = CGBitmapContextGetHeight(effectOutContext),
		.rowBytes = CGBitmapContextGetBytesPerRow(effectOutContext)
	};
}

- (void) forceRefresh {
	_currentFrameInterval = _frameInterval - 1;
	[self refresh];
}

- (void) refresh {
	if (++_currentFrameInterval < _frameInterval) {
		return;
	}
	_currentFrameInterval = 0;
	
	CALayer *blurTargetLayer = _customBlurTargetLayer ? _customBlurTargetLayer : self.superlayer;
	
#ifdef DEBUG
	// generates a shadow copy
	NSParameterAssert(self.presentationLayer);
	NSParameterAssert(blurTargetLayer);
	NSParameterAssert(_effectInContext);
	NSParameterAssert(_effectOutContext);
#endif
	
	CGContextRef effectInContext = CGContextRetain(_effectInContext);
	CGContextRef effectOutContext = CGContextRetain(_effectOutContext);
	vImage_Buffer effectInBuffer = _effectInBuffer;
	vImage_Buffer effectOutBuffer = _effectOutBuffer;
	
	self.hidden = YES;
	[blurTargetLayer renderInContext:effectInContext];
	self.hidden = NO;
	
	uint32_t blurKernel = _precalculatedBlurKernel;
	
	vImageBoxConvolve_ARGB8888(&effectInBuffer, &effectOutBuffer, NULL, 0, 0, blurKernel, blurKernel, 0, kvImageEdgeExtend);
	vImageBoxConvolve_ARGB8888(&effectOutBuffer, &effectInBuffer, NULL, 0, 0, blurKernel, blurKernel, 0, kvImageEdgeExtend);
	vImageBoxConvolve_ARGB8888(&effectInBuffer, &effectOutBuffer, NULL, 0, 0, blurKernel, blurKernel, 0, kvImageEdgeExtend);
	
	CGImageRef outImage = CGBitmapContextCreateImage(effectOutContext);
	self.contents = (__bridge id)(outImage);
	CGImageRelease(outImage);
	
	CGContextRelease(effectInContext);
	CGContextRelease(effectOutContext);
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if (context == LFGlassLayerBlurRadiusObserverContext) {
		[self updatePrecalculatedBlurKernel];
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

+ (id<CAAction>) defaultActionForKey:(NSString *)event {
	if ([event isEqualToString:@"blurRadius"]) {
		CATransition *blurAnimation = [CATransition animation];
		blurAnimation.type = kCATransitionFade;
		return blurAnimation;
	}
	return [super defaultActionForKey:event];
}

@end
