#import <Cocoa/Cocoa.h>

// Shows a dimmed, full-screen "look into the distance" overlay on every screen
// while a break is in progress, with a live countdown and a Skip button.
@interface BreakOverlayController : NSObject

// Called when the user clicks "Skip".
@property (nonatomic, copy) void (^onSkip)(void);

- (void)show;
- (void)hide;
- (void)updateSecondsRemaining:(NSInteger)seconds;

@end
