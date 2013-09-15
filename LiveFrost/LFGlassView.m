#import "LFGlassView.h"
#import "LFDisplayBridge.h"

@interface LFGlassView () <LFDisplayBridgeTriggering>

@property (nonatomic, assign, readonly) uint32_t precalculatedBlurKernel;
- (void)updatePrecalculatedBlurKernelWithBlurRadius:(CGFloat)blurRadius;

@end

@implementation LFGlassView

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
}

- (void) willMoveToSuperview:(UIView*)superview {
	if (superview) {
		[[LFDisplayBridge sharedInstance] addSubscribedViewsObject:self];
	} else {
		[[LFDisplayBridge sharedInstance] removeSubscribedViewsObject:self];
	}
}

- (void) setBlurRadius:(CGFloat)blurRadius
{
	if (blurRadius == _blurRadius) {
		return;
	}
	
	[self willChangeValueForKey:@"blurRadius"];
	
	_blurRadius = blurRadius;
	[self updatePrecalculatedBlurKernelWithBlurRadius:blurRadius];
	
	[self didChangeValueForKey:@"blurRadius"];
}

- (void)updatePrecalculatedBlurKernelWithBlurRadius:(CGFloat)blurRadius
{
	uint32_t radius = (uint32_t)floor(blurRadius * 3. * sqrt(2 * M_PI) / 4 + 0.5);
	radius += (radius + 1) % 2;
	_precalculatedBlurKernel = radius;
}

- (void) refresh {
	UIView *superview = self.superview;
	
	CGRect visibleRect = self.frame;
	CGSize scaledSize = (CGSize){
		_scaleFactor * CGRectGetWidth(visibleRect),
		_scaleFactor * CGRectGetHeight(visibleRect)
	};
	
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	
	CGContextRef effectInContext = CGBitmapContextCreate(NULL, scaledSize.width, scaledSize.height, 8, scaledSize.width * 8, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	
	vImage_Buffer effectInBuffer = (vImage_Buffer){
		.data = CGBitmapContextGetData(effectInContext),
		.width = CGBitmapContextGetWidth(effectInContext),
		.height = CGBitmapContextGetHeight(effectInContext),
		.rowBytes = CGBitmapContextGetBytesPerRow(effectInContext)
	};
	
	CGContextRef effectOutContext = CGBitmapContextCreate(NULL, scaledSize.width, scaledSize.height, 8, scaledSize.width * 8, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	
	vImage_Buffer effectOutBuffer = (vImage_Buffer){
		.data = CGBitmapContextGetData(effectOutContext),
		.width = CGBitmapContextGetWidth(effectOutContext),
		.height = CGBitmapContextGetHeight(effectOutContext),
		.rowBytes = CGBitmapContextGetBytesPerRow(effectOutContext)
	};
	
	CGColorSpaceRelease(colorSpace);
	
	CGContextConcatCTM(effectInContext, (CGAffineTransform){
		.a = 1,
		.b = 0,
		.c = 0,
		.d = -1,
		.tx = 0,
		.ty = scaledSize.height
	});
	CGContextScaleCTM(effectInContext, _scaleFactor, _scaleFactor);
	CGContextTranslateCTM(effectInContext, -visibleRect.origin.x, -visibleRect.origin.y);
	
	dispatch_async(dispatch_get_main_queue(), ^{
		self.hidden = YES;
		[superview.layer renderInContext:effectInContext];
		self.hidden = NO;
		
		[[LFDisplayBridge sharedInstance] executeBlockOnRenderQueue:^{
			uint32_t blurKernel = _precalculatedBlurKernel;
			
			vImageBoxConvolve_ARGB8888(&effectInBuffer, &effectOutBuffer, NULL, 0, 0, blurKernel, blurKernel, 0, kvImageEdgeExtend);
			vImageBoxConvolve_ARGB8888(&effectOutBuffer, &effectInBuffer, NULL, 0, 0, blurKernel, blurKernel, 0, kvImageEdgeExtend);
			vImageBoxConvolve_ARGB8888(&effectInBuffer, &effectOutBuffer, NULL, 0, 0, blurKernel, blurKernel, 0, kvImageEdgeExtend);
			
			CGImageRef outImage = CGBitmapContextCreateImage(effectOutContext);
			
			CGContextRelease(effectInContext);
			CGContextRelease(effectOutContext);
			
			dispatch_async(dispatch_get_main_queue(), ^{
				self.layer.contents = (__bridge id)(outImage);
				CGImageRelease(outImage);
			});
		} waitUntilDone:NO];
	});
}

@end