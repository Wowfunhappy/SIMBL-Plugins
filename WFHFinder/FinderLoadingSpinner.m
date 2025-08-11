//@run: make install

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "ZKSwizzle.h"

// Loading spinner overlay that displays while Finder loads directory contents
@interface LoadingSpinnerView : NSView {
    NSProgressIndicator *_spinner;
}
@property (nonatomic, strong) NSProgressIndicator *spinner;
@end

@implementation LoadingSpinnerView

@synthesize spinner = _spinner;

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Create progress indicator (spinner)
        NSProgressIndicator *progressIndicator = [[NSProgressIndicator alloc] init];
        [progressIndicator setStyle:NSProgressIndicatorSpinningStyle];
        [progressIndicator setControlSize:NSRegularControlSize];
        [progressIndicator setDisplayedWhenStopped:NO];
        [progressIndicator setIndeterminate:YES];
        [progressIndicator sizeToFit];
        
        // Center the spinner
        NSRect spinnerFrame = [progressIndicator frame];
        spinnerFrame.origin.x = (frame.size.width - spinnerFrame.size.width) / 2;
        spinnerFrame.origin.y = (frame.size.height - spinnerFrame.size.height) / 2;
        [progressIndicator setFrame:spinnerFrame];
        
        [self addSubview:progressIndicator];
        self.spinner = progressIndicator;
    }
    return self;
}

- (void)startAnimating {
    [self.spinner startAnimation:nil];
}

- (void)stopAnimating {
    [self.spinner stopAnimation:nil];
}

@end

// Hook TBrowserContainerController to track population state
@interface LoadingSpinner_TBrowserContainerController : NSObject
@end

@implementation LoadingSpinner_TBrowserContainerController

static NSMutableDictionary *pendingSpinners = nil;

+ (void)initialize {
    if (self == [LoadingSpinner_TBrowserContainerController class]) {
        pendingSpinners = [[NSMutableDictionary alloc] init];
    }
}

- (void)setIsPopulationInProgress:(BOOL)inProgress {
    // Ensure dictionary is initialized
    if (!pendingSpinners) {
        pendingSpinners = [[NSMutableDictionary alloc] init];
    }
    
    // Get the browser view
    id browserViewController = [self browserViewController];
    NSView *browserView = nil;
    
    if (browserViewController && [browserViewController respondsToSelector:@selector(browserView)]) {
        browserView = [browserViewController performSelector:@selector(browserView)];
    }
    
    if (browserView) {
        NSString *key = [NSString stringWithFormat:@"%p", browserView];
        
        if (inProgress) {
            // Cancel any existing timer for this view
            NSTimer *existingTimer = [pendingSpinners objectForKey:key];
            if (existingTimer) {
                [existingTimer invalidate];
            }
            
            // Schedule spinner to show after 1 second
            NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                              target:self
                                                            selector:@selector(showSpinnerForTimer:)
                                                            userInfo:@{@"view": browserView}
                                                            repeats:NO];
            [pendingSpinners setObject:timer forKey:key];
        } else {
            // Cancel pending spinner if loading finished quickly
            NSTimer *timer = [pendingSpinners objectForKey:key];
            if (timer) {
                [timer invalidate];
                [pendingSpinners removeObjectForKey:key];
            }
            
            // Hide spinner if it's showing
            LoadingSpinnerView *spinner = objc_getAssociatedObject(browserView, "LoadingSpinner");
            if (spinner) {
                [spinner stopAnimating];
                [spinner removeFromSuperview];
                objc_setAssociatedObject(browserView, "LoadingSpinner", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    }
    
    ZKOrig(void, inProgress);
}

- (void)showSpinnerForTimer:(NSTimer *)timer {
    NSView *browserView = [[timer userInfo] objectForKey:@"view"];
    if (!browserView) return;
    
    NSString *key = [NSString stringWithFormat:@"%p", browserView];
    [pendingSpinners removeObjectForKey:key];
    
    // Remove any existing spinner
    LoadingSpinnerView *existingSpinner = objc_getAssociatedObject(browserView, "LoadingSpinner");
    if (existingSpinner) {
        [existingSpinner stopAnimating];
        [existingSpinner removeFromSuperview];
    }
    
    // Create and add new spinner
    LoadingSpinnerView *spinner = [[LoadingSpinnerView alloc] initWithFrame:[browserView bounds]];
    [spinner setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    objc_setAssociatedObject(browserView, "LoadingSpinner", spinner, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [browserView addSubview:spinner];
    [spinner startAnimating];
}

@end

@implementation NSObject (LoadingSpinnerMain)

+ (void)load {
    ZKSwizzle(LoadingSpinner_TBrowserContainerController, TBrowserContainerController);
}

@end