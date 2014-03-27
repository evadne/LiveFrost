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
// Contains contributions from Nam Kennic
//

#import "LFGlassView.h"
#import "LFDisplayBridge.h"

@interface LFGlassView () <LFDisplayBridgeTriggering>

@property (nonatomic, assign, readonly) CGSize cachedBufferSize;
@property (nonatomic, assign, readonly) CGSize scaledSize;

@property (nonatomic, assign, readonly) CGContextRef effectInContext;
@property (nonatomic, assign, readonly) CGContextRef effectOutContext;

@property (nonatomic, assign, readonly) vImage_Buffer effectInBuffer;
@property (nonatomic, assign, readonly) vImage_Buffer effectOutBuffer;

@property (nonatomic, assign, readonly) uint32_t precalculatedBlurKernel;

@property (nonatomic, assign, readonly) BOOL shouldLiveBlur;

@property (nonatomic, assign, readonly) NSUInteger currentFrameInterval;

@property (nonatomic, strong, readonly) CALayer *backgroundColorLayer;

- (void) updatePrecalculatedBlurKernel;
- (void) adjustImageBuffersAndLayerFromFrame:(CGRect)fromFrame;
- (void) recreateImageBuffers;
- (void) startLiveBlurringIfReady;
- (void) stopLiveBlurring;
- (BOOL) isReadyToLiveBlur;
- (void) forceRefresh;

@end

#if !__has_feature(objc_arc)
	#error This implementation file must be compiled with Objective-C ARC.

	#error Compile this file with the -fobjc-arc flag under your target's Build Phases,
	#error   or convert your project to Objective-C ARC.
#endif

@implementation LFGlassView
@dynamic scaledSize;
@dynamic liveBlurring;

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
	self.clipsToBounds = YES;
	self.blurRadius = 4.0f;
	_backgroundColorLayer = [CALayer layer];
	_backgroundColorLayer.actions = @{
		@"backgroundColor": [NSNull null],
		@"bounds": [NSNull null],
		@"position": [NSNull null]
	};
	self.backgroundColor = [UIColor clearColor];
	self.scaleFactor = 0.25f;
	self.opaque = NO;
	self.userInteractionEnabled = NO;
	self.layer.actions = @{
		@"contents": [NSNull null]
	};
	_shouldLiveBlur = YES;
	_frameInterval = 1;
	_currentFrameInterval = 0;
}

- (void) dealloc {
	if (_effectInContext) {
		CGContextRelease(_effectInContext);
	}
	if (_effectOutContext) {
		CGContextRelease(_effectOutContext);
	}
	[self stopLiveBlurring];
}

- (void) setBlurRadius:(CGFloat)blurRadius {
	_blurRadius = blurRadius;
	[self updatePrecalculatedBlurKernel];
}

- (void) updatePrecalculatedBlurKernel {
	uint32_t radius = (uint32_t)floor(_blurRadius * 3. * sqrt(2 * M_PI) / 4 + 0.5);
	radius += (radius + 1) % 2;
	_precalculatedBlurKernel = radius;
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
	CGSize scaledSize = (CGSize){
		_scaleFactor * CGRectGetWidth(self.bounds),
		_scaleFactor * CGRectGetHeight(self.bounds)
	};
	return scaledSize;
}

- (void) setFrame:(CGRect)frame {
	CGRect fromFrame = self.frame;
	[super setFrame:frame];
	[self adjustImageBuffersAndLayerFromFrame:fromFrame];
}

- (void) setBounds:(CGRect)bounds {
	CGRect fromFrame = self.frame;
	[super setBounds:bounds];
	[self adjustImageBuffersAndLayerFromFrame:fromFrame];
}

- (void) setCenter:(CGPoint)center {
	CGRect fromFrame = self.frame;
	[super setCenter:center];
	[self adjustImageBuffersAndLayerFromFrame:fromFrame];
}

- (void) setBackgroundColor:(UIColor *)color {
	[super setBackgroundColor:color];
	
	CGColorRef backgroundCGColor = [color CGColor];
	
	if (CGColorGetAlpha(backgroundCGColor)) {
		_backgroundColorLayer.backgroundColor = backgroundCGColor;
		[self.layer insertSublayer:_backgroundColorLayer atIndex:0];
	} else {
		[_backgroundColorLayer removeFromSuperlayer];
	}
}

- (void) adjustImageBuffersAndLayerFromFrame:(CGRect)fromFrame {
	if (CGRectEqualToRect(fromFrame, self.frame)) {
		return;
	}
	
	_backgroundColorLayer.frame = self.bounds;
	
	if (!CGRectIsEmpty(self.bounds)) {
		[self recreateImageBuffers];
	} else {
		[self stopLiveBlurring];
		return;
	}
	
	[self startLiveBlurringIfReady];
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
		[self forceRefresh];
		[[LFDisplayBridge sharedInstance] addSubscribedViewsObject:self];
	}
}

- (void) stopLiveBlurring {
	[[LFDisplayBridge sharedInstance] removeSubscribedViewsObject:self];
}

- (BOOL) isReadyToLiveBlur {
	return (!CGRectIsEmpty(self.bounds) && self.superview && self.window && _shouldLiveBlur);
}

- (BOOL) blurOnceIfPossible {
	if (!CGRectIsEmpty(self.bounds) && self.layer.presentationLayer) {
		[self forceRefresh];
		return YES;
	} else {
		return NO;
	}
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

- (void) recreateImageBuffers {
	CGRect visibleRect = self.frame;
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
	
	UIView *superview = self.superview;
#ifdef DEBUG
	NSParameterAssert(superview);
	NSParameterAssert(self.window);
	NSParameterAssert(_effectInContext);
	NSParameterAssert(_effectOutContext);
#endif
	
	CGContextRef effectInContext = CGContextRetain(_effectInContext);
	CGContextRef effectOutContext = CGContextRetain(_effectOutContext);
	vImage_Buffer effectInBuffer = _effectInBuffer;
	vImage_Buffer effectOutBuffer = _effectOutBuffer;
	
	self.hidden = YES;
	[superview.layer renderInContext:effectInContext];
	self.hidden = NO;
	
	uint32_t blurKernel = _precalculatedBlurKernel;
	
	vImageBoxConvolve_ARGB8888(&effectInBuffer, &effectOutBuffer, NULL, 0, 0, blurKernel, blurKernel, 0, kvImageEdgeExtend);
	vImageBoxConvolve_ARGB8888(&effectOutBuffer, &effectInBuffer, NULL, 0, 0, blurKernel, blurKernel, 0, kvImageEdgeExtend);
	vImageBoxConvolve_ARGB8888(&effectInBuffer, &effectOutBuffer, NULL, 0, 0, blurKernel, blurKernel, 0, kvImageEdgeExtend);
	
	CGImageRef outImage = CGBitmapContextCreateImage(effectOutContext);
	self.layer.contents = (__bridge id)(outImage);
	CGImageRelease(outImage);
    
	CGContextRelease(effectInContext);
	CGContextRelease(effectOutContext);
}

@end
