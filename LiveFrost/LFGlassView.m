#import "LFGlassView.h"
#import "LFDisplayBridge.h"

@interface LFGlassView () <LFDisplayBridgeTriggering>

@property (nonatomic, assign, readonly) CGSize bufferSize;
@property (nonatomic, assign, readonly) CGSize scaledSize;

@property (nonatomic, assign, readonly) CGContextRef effectInContext;
@property (nonatomic, assign, readonly) CGContextRef effectOutContext;

@property (nonatomic, assign, readonly) vImage_Buffer effectInBuffer;
@property (nonatomic, assign, readonly) vImage_Buffer effectOutBuffer;

@property (nonatomic, assign, readonly) uint32_t precalculatedBlurKernel;

- (void) updatePrecalculatedBlurKernel;
- (void) adjustImageBuffersForFrame:(CGRect)frame fromFrame:(CGRect)fromFrame;
- (void) recreateImageBuffers;
- (void) subscribeViewWithBounds:(CGRect)bounds;

@end

@implementation LFGlassView
@dynamic scaledSize;

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
	self.layer.cornerRadius = 20.0f;
	self.blurRadius = 4.0f;
	self.scaleFactor = 0.25f;
	self.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.25f];
	self.opaque = NO;
	self.userInteractionEnabled = NO;
	self.layer.actions = @{
		@"contents": [NSNull null]
	};
}

- (void) dealloc {
	if (_effectInContext) {
		CGContextRelease(_effectInContext);
	}
	if (_effectOutContext) {
		CGContextRelease(_effectOutContext);
	}
	[[LFDisplayBridge sharedInstance] removeSubscribedViewsObject:self];
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
	CGSize scaledSize = [self scaledSize];
	if (!CGSizeEqualToSize(_bufferSize, scaledSize)) {
		_bufferSize = scaledSize;
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
	[self adjustImageBuffersForFrame:self.frame fromFrame:fromFrame];
	[self subscribeViewWithBounds:frame];
}

- (void) setBounds:(CGRect)bounds {
	CGRect fromFrame = self.frame;
	[super setBounds:bounds];
	[self adjustImageBuffersForFrame:self.frame fromFrame:fromFrame];
	[self subscribeViewWithBounds:bounds];
}

- (void) setCenter:(CGPoint)center {
	CGRect fromFrame = self.frame;
	[super setCenter:center];
	[self adjustImageBuffersForFrame:self.frame fromFrame:fromFrame];
}

- (void) adjustImageBuffersForFrame:(CGRect)frame fromFrame:(CGRect)fromFrame {
	if (CGRectEqualToRect(fromFrame, frame)) {
		return;
	}
	
	if (!CGRectIsEmpty(frame) && self.superview) {
		[self recreateImageBuffers];
		[self refresh];
	}
}

- (void) recreateImageBuffers {	
	CGRect visibleRect = self.frame;
	CGSize bufferSize = self.scaledSize;
	if (CGSizeEqualToSize(bufferSize, CGSizeZero)) {
		return;
	}
	
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	
	CGContextRef effectInContext = CGBitmapContextCreate(NULL, bufferSize.width, bufferSize.height, 8, bufferSize.width * 8, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	
	CGContextRef effectOutContext = CGBitmapContextCreate(NULL, bufferSize.width, bufferSize.height, 8, bufferSize.width * 8, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	
	CGColorSpaceRelease(colorSpace);
	
	CGContextConcatCTM(effectInContext, (CGAffineTransform){
		1, 0, 0, -1, 0, bufferSize.height
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

- (void) subscribeViewWithBounds:(CGRect)bounds {
	if (!CGRectIsEmpty(bounds) && self.superview) {
		[[LFDisplayBridge sharedInstance] addSubscribedViewsObject:self];
	} else {
		[[LFDisplayBridge sharedInstance] removeSubscribedViewsObject:self];
	}
}

- (void) didMoveToSuperview {
	[super didMoveToSuperview];
	
	if (!CGRectIsEmpty(self.bounds) && self.superview) {
		[self recreateImageBuffers];
		[self refresh];
		[[LFDisplayBridge sharedInstance] addSubscribedViewsObject:self];
	}
}

- (void) removeFromSuperview {
	[[LFDisplayBridge sharedInstance] removeSubscribedViewsObject:self];
	
	[super removeFromSuperview];
}

- (void) refresh {
#ifdef DEBUG
    NSParameterAssert(self.superview);
    NSParameterAssert(_effectInContext);
    NSParameterAssert(_effectOutContext);
#endif
	
	CGContextRef effectInContext = _effectInContext;
	CGContextRef effectOutContext = _effectOutContext;
	vImage_Buffer effectInBuffer = _effectInBuffer;
	vImage_Buffer effectOutBuffer = _effectOutBuffer;
	
	self.hidden = YES;
	[self.superview.layer renderInContext:effectInContext];
	self.hidden = NO;
	
	uint32_t blurKernel = _precalculatedBlurKernel;
	
	vImageBoxConvolve_ARGB8888(&effectInBuffer, &effectOutBuffer, NULL, 0, 0, blurKernel, blurKernel, 0, kvImageEdgeExtend);
	vImageBoxConvolve_ARGB8888(&effectOutBuffer, &effectInBuffer, NULL, 0, 0, blurKernel, blurKernel, 0, kvImageEdgeExtend);
	vImageBoxConvolve_ARGB8888(&effectInBuffer, &effectOutBuffer, NULL, 0, 0, blurKernel, blurKernel, 0, kvImageEdgeExtend);
	
	CGImageRef outImage = CGBitmapContextCreateImage(effectOutContext);
	self.layer.contents = (__bridge id)(outImage);
	CGImageRelease(outImage);
}

@end