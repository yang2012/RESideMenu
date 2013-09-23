//
//  RESideMenu.m
// RESideMenu
//
// Copyright (c) 2013 Roman Efimov (https://github.com/romaonthego)
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

#import "RESideMenu.h"
#import "AccelerationAnimation.h"
#import "Evaluate.h"
#import "UIView+ImageSnapshot.h"
#import "UINavigationController+DelegateFixes.h"

const int INTERSTITIAL_STEPS = 99;

NSString * const RESideMenuWillOpen = @"RESideMenuWillOpen";
NSString * const RESideMenuDidOpen = @"RESideMenuDidOpen";
NSString * const RESideMenuDidClose = @"RESideMenuDidClose";

@interface RESideMenu () {
    BOOL _appIsHidingStatusBar;
    BOOL _isInSubMenu;
    BOOL _showFromPan;
}

@property (assign, readwrite, nonatomic) CGFloat initialX;
@property (assign, readwrite, nonatomic) CGSize originalSize;
@property (strong, readonly, nonatomic) UIImageView *screenshotView;
@property (strong, nonatomic) UIViewController *topController;

@end

@implementation RESideMenu
@synthesize backgroundView = _backgroundView;

- (id)init
{
    if (self = [super init]) {
        self.verticalPortraitOffset = self.verticalLandscapeOffset = 100;
        self.horizontalPortraitOffset = self.horizontalLandscapeOffset = 50;
        self.hideStatusBarArea = YES;
        self.openStatusBarStyle = UIStatusBarStyleDefault;
    }
    
    return self;
}

#pragma mark -
#pragma markPublic API

- (void)show
{
    if (_isShowing)
        return;

    [[NSNotificationCenter defaultCenter] postNotificationName:RESideMenuWillOpen object:nil];
    _isShowing = YES;
    _showFromPan = NO;
    
    // Keep track of whether or not it was already hidden
    //
    _appIsHidingStatusBar = [[UIApplication sharedApplication] isStatusBarHidden];
    
    if (!_appIsHidingStatusBar && _hideStatusBarArea)
        [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
    
    [self updateStatusBar];
    [self performSelector:@selector(showAfterDelay) withObject:nil afterDelay:0.1];
}

- (void)showFromPanGesture:(UIPanGestureRecognizer *)sender
{
    CGPoint translation = [sender translationInView:self.view];
    
    _showFromPan = YES;
	if (sender.state == UIGestureRecognizerStateBegan) {
        if (_isShowing || translation.x<=0)
            return;
        
        _isShowing = YES;
        
        if (!_appIsHidingStatusBar && _hideStatusBarArea)
            [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
        
        [self updateStatusBar];
        
        [self updateViews];
        _screenshotView.frame = CGRectMake(0, 0, _originalSize.width, _originalSize.height);
        
	}
    
    [self panGestureRecognized:sender];
}

- (void)hide
{
    if (!_isShowing)
        return;
    
    [self restoreFromRect:_screenshotView.frame];
}

- (void)displayContentController:(UIViewController *)content;
{
    if (self.topController) {
        [self.topController willMoveToParentViewController:nil];
        [self.topController.view removeFromSuperview];
        [self.topController removeFromParentViewController];
    }
    
    [self addChildViewController:content];
    content.view.frame = self.view.bounds;
    [self.view addSubview:content.view];
    [content didMoveToParentViewController:self];
    
    self.topController = content;
    
    [self.topController.view setNeedsDisplay];
    [self.view bringSubviewToFront:_backgroundView];
    [self.view bringSubviewToFront:_contentContainerView];
    [self.view bringSubviewToFront:_screenshotView];

    __typeof (&*self) __weak weakSelf = self;
    double delayInSeconds = 0.1;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        _screenshotView.image = [weakSelf.topController.view snapshotImage];
        if (_isShowing)
            [weakSelf hide];
    });
}

- (void)addAnimation:(NSString *)path view:(UIView *)view startValue:(double)startValue endValue:(double)endValue
{
    AccelerationAnimation *animation = [AccelerationAnimation animationWithKeyPath:path
                                                                        startValue:startValue
                                                                          endValue:endValue
                                                                  evaluationObject:[[ExponentialDecayEvaluator alloc] initWithCoefficient:6.0]
                                                                 interstitialSteps:INTERSTITIAL_STEPS];
    animation.removedOnCompletion = NO;
    [view.layer addAnimation:animation forKey:path];
}

#pragma mark -
#pragma mark Private API

- (void)showAfterDelay
{
    [self updateViews];
    [self minimizeFromRect:CGRectMake(0, 0, _originalSize.width, _originalSize.height)];
}


- (REBackgroundView*)backgroundView
{
    if(!_backgroundView) {
        _backgroundView = [[REBackgroundView alloc] initWithFrame:CGRectMake(0, -20, self.view.bounds.size.width, self.view.bounds.size.height + 20)];
        _backgroundView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
        _backgroundView.backgroundImage = _backgroundImage;
    }
    return _backgroundView;
}

- (UIView *)contentContainerView
{
    if(!_contentContainerView) {
        _contentContainerView = [[UIView alloc] initWithFrame:CGRectMake(self.backgroundView.frame.origin.x, self.backgroundView.frame.origin.y, self.backgroundView.frame.size.width, self.backgroundView.frame.size.height)];
        _contentContainerView.backgroundColor = [UIColor clearColor];
        _contentContainerView.alpha = 0;
        _contentContainerView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    }
    return _contentContainerView;
}

- (void)updateViews
{
    // Take a snapshot
    //
    _screenshotView = [[UIImageView alloc] initWithFrame:CGRectNull];
    _screenshotView.image = [self.topController.view snapshotImage];
    _screenshotView.frame = CGRectMake(0, 0, _screenshotView.image.size.width, _screenshotView.image.size.height);
    _screenshotView.userInteractionEnabled = YES;
    _screenshotView.layer.anchorPoint = CGPointMake(0, 0);
    _screenshotView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    _originalSize = _screenshotView.frame.size;
    
    
    // Add views
    //
    if(!self.backgroundView.superview)
        [self.view addSubview:_backgroundView];
    
    self.contentContainerView.alpha = 0;
    [self.view addSubview:self.contentContainerView];
    
    [self.view addSubview:_screenshotView];
    
    // Gestures
    UIPanGestureRecognizer *panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panGestureRecognized:)];
    [_screenshotView addGestureRecognizer:panGestureRecognizer];
    
    UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapGestureRecognized:)];
    [_screenshotView addGestureRecognizer:tapGestureRecognizer];

    [[NSNotificationCenter defaultCenter] postNotificationName:RESideMenuDidOpen object:nil];
}

- (void)minimizeFromRect:(CGRect)rect
{
    CGFloat widthOffset = self.view.bounds.size.width / (UIDeviceOrientationIsPortrait([[UIApplication sharedApplication] statusBarOrientation]) ? 6 : 3);
    
    CGFloat m = 1 - (((self.view.bounds.size.width - widthOffset) / self.view.bounds.size.width) * 150.0 / self.view.bounds.size.width);
    CGFloat newWidth = _originalSize.width * m;
    CGFloat newHeight = _originalSize.height * m;
    
    [CATransaction begin];
    [CATransaction setValue:[NSNumber numberWithFloat:0.6] forKey:kCATransactionAnimationDuration];
    
    [self addAnimation:@"position.x" view:_screenshotView startValue:rect.origin.x endValue:self.view.bounds.size.width - widthOffset];
    [self addAnimation:@"position.y" view:_screenshotView startValue:rect.origin.y endValue:(self.view.bounds.size.height - newHeight) / 2.0];
    [self addAnimation:@"bounds.size.width" view:_screenshotView startValue:rect.size.width endValue:newWidth];
    [self addAnimation:@"bounds.size.height" view:_screenshotView startValue:rect.size.height endValue:newHeight];
    
    _screenshotView.layer.anchorPoint = CGPointMake(0, 0);
    _screenshotView.layer.position = CGPointMake(self.view.bounds.size.width - widthOffset, (self.view.bounds.size.height - newHeight) / 2.0);
    _screenshotView.layer.bounds = CGRectMake(self.view.bounds.size.width - widthOffset, (self.view.bounds.size.height - newHeight) / 2.0, newWidth, newHeight);
    [CATransaction commit];
    
    if (_contentContainerView.alpha  != 1 ) {
        __typeof (&*self) __weak weakSelf = self;
        
        if(_contentContainerView.alpha == 0){
            weakSelf.contentContainerView.transform = CGAffineTransformScale(CGAffineTransformIdentity, 0.9, 0.9);
        }
        
        [UIView animateWithDuration:0.5 animations:^{
            weakSelf.contentContainerView.transform = CGAffineTransformIdentity;
        }];
        
        [UIView animateWithDuration:0.6 animations:^{
            weakSelf.contentContainerView.alpha = 1;
        }];
    }
}

- (void)restoreFromRect:(CGRect)rect
{
    _screenshotView.userInteractionEnabled = NO;
    
    [CATransaction begin];
    [CATransaction setValue:[NSNumber numberWithFloat:0.4] forKey:kCATransactionAnimationDuration];
    [self addAnimation:@"position.x" view:_screenshotView startValue:rect.origin.x endValue:0];
    [self addAnimation:@"position.y" view:_screenshotView startValue:rect.origin.y endValue:0];
    [self addAnimation:@"bounds.size.width" view:_screenshotView startValue:rect.size.width endValue:self.view.bounds.size.width];
    [self addAnimation:@"bounds.size.height" view:_screenshotView startValue:rect.size.height endValue:self.view.bounds.size.height];
    
    _screenshotView.layer.position = CGPointMake(0, 0);
    _screenshotView.layer.bounds = CGRectMake(0, 0, self.view.bounds.size.width, self.view.bounds.size.height);
    [CATransaction commit];
    [self performSelector:@selector(restoreView) withObject:nil afterDelay:0.4];
    
    __typeof (&*self) __weak weakSelf = self;
    [UIView animateWithDuration:0.3 animations:^{
        weakSelf.contentContainerView.alpha = 0;
        weakSelf.contentContainerView.transform = CGAffineTransformScale(CGAffineTransformIdentity, 0.9, 0.9);
    }];
    
    // Restore the status bar to its original state
    //
    [[UIApplication sharedApplication] setStatusBarHidden:_appIsHidingStatusBar withAnimation:UIStatusBarAnimationFade];

    _isShowing = NO;
    [self updateStatusBar];
}

- (void) updateStatusBar
{
    if ([self respondsToSelector:@selector(setNeedsStatusBarAppearanceUpdate)]) {
        __typeof (&*self) __weak weakSelf = self;
        [UIView animateWithDuration:0.3 animations:^{
            [weakSelf performSelector:@selector(setNeedsStatusBarAppearanceUpdate)];
        }];
    }
}

- (void)restoreView
{
    [_backgroundView removeFromSuperview];
    [_contentContainerView removeFromSuperview];
    
    __typeof (&*self) __weak weakSelf = self;
    [UIView animateWithDuration:0.1 animations:^{
        weakSelf.screenshotView.alpha = 0;
    } completion:^(BOOL finished) {
        [weakSelf.screenshotView removeFromSuperview];
        _isShowing = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:RESideMenuDidClose object:nil];
    }];
}

- (CGFloat)verticalOffset
{
    if (UIDeviceOrientationIsPortrait([[UIApplication sharedApplication] statusBarOrientation])) {
        return self.verticalPortraitOffset;
    } else {
        return self.verticalLandscapeOffset;
    }
}

- (CGFloat)horizontalOffset
{
    if (UIDeviceOrientationIsPortrait([[UIApplication sharedApplication] statusBarOrientation])) {
        return self.horizontalPortraitOffset;
    } else {
        return self.horizontalLandscapeOffset;
    }
}

#pragma mark -
#pragma mark Gestures

- (void)panGestureRecognized:(UIPanGestureRecognizer *)sender
{
    CGPoint translation = [sender translationInView:self.view];
	if (sender.state == UIGestureRecognizerStateBegan) {
        if (_showFromPan){
            _initialX = 0;
        } else {
            _initialX = _screenshotView.frame.origin.x;
        }
        _contentContainerView.transform = CGAffineTransformIdentity;
	}
	
    if (sender.state == UIGestureRecognizerStateChanged) {
        _screenshotView.layer.anchorPoint = CGPointMake(0, 0);
        
        CGFloat x = translation.x + _initialX ;
        CGFloat m = 1 - ((x / self.view.bounds.size.width) * 150.0 / self.view.bounds.size.width);
        CGFloat y = (self.view.bounds.size.height - _originalSize.height * m) / 2.0;
        
        CGFloat widthOffset = self.view.bounds.size.width / (UIDeviceOrientationIsPortrait([[UIApplication sharedApplication] statusBarOrientation]) ? 4 : 3);
        
        float alphaOffset = (x + widthOffset) / self.view.bounds.size.width;
        _contentContainerView.alpha = alphaOffset;
        float scaleOffset = 0.6 +(alphaOffset*0.4);
        _contentContainerView.transform = CGAffineTransformScale(CGAffineTransformIdentity, scaleOffset, scaleOffset);
        
        if (x < 0 || y < 0) {
            _screenshotView.frame = CGRectMake(0, 0, _originalSize.width, _originalSize.height);
        } else {
            _screenshotView.frame = CGRectMake(x, y, _originalSize.width * m, _originalSize.height * m);
        }
    }

    if (sender.state == UIGestureRecognizerStateEnded && _screenshotView) {
        if ([sender velocityInView:self.view].x < 0) {
            [self restoreFromRect:_screenshotView.frame];
        } else {
            _showFromPan = NO;
            [self minimizeFromRect:_screenshotView.frame];
        }
    }
}

- (void)tapGestureRecognized:(UITapGestureRecognizer *)sender
{
    [self restoreFromRect:_screenshotView.frame];
}

#pragma mark - Status bar

#ifdef __IPHONE_7_0
- (UIStatusBarStyle)preferredStatusBarStyle
{
    return _isShowing ? self.openStatusBarStyle : [self.topController preferredStatusBarStyle];
}
#endif

@end
