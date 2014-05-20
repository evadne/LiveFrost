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

#import "LFDisplayBridge.h"

void LF_refreshAllSubscribedObjectsApplierFunction(const void *value, void *context);

@interface LFDisplayBridge ()

@property (nonatomic, readwrite, assign) CFMutableSetRef subscribedObjects;
@property (nonatomic, readonly, strong) CADisplayLink *displayLink;

@end

void LF_refreshAllSubscribedObjectsApplierFunction(const void *value, void *context) {
	[(__bridge id<LFDisplayBridgeTriggering>)value refresh];
}

#if !__has_feature(objc_arc)
#error This implementation file must be compiled with Objective-C ARC.

#error Compile this file with the -fobjc-arc flag under your target's Build Phases,
#error	 or convert your project to Objective-C ARC.
#endif

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
		_subscribedObjects = CFSetCreateMutable(kCFAllocatorDefault, 0, NULL);
		_displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(handleDisplayLink:)];
		[_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
	}
	return self;
}

- (void) dealloc {
	[_displayLink invalidate];
	CFRelease(_subscribedObjects);
}

- (void) addSubscribedObject:(id<LFDisplayBridgeTriggering>)object {
	CFSetAddValue(_subscribedObjects, (__bridge const void*)object);
}

- (void) removeSubscribedObject:(id<LFDisplayBridgeTriggering>)object {
	CFSetRemoveValue(_subscribedObjects, (__bridge const void*)object);
}

- (void) handleDisplayLink:(CADisplayLink *)displayLink {
	[self refresh];
}

- (void) refresh {
	CFSetApplyFunction(_subscribedObjects, LF_refreshAllSubscribedObjectsApplierFunction, NULL);
}

@end
