#import "AppDelegate.h"
#import "BreakOverlayController.h"
#import <CoreGraphics/CoreGraphics.h>
#import <ServiceManagement/ServiceManagement.h>

// Tunables.
static const NSInteger kWorkInterval       = 20 * 60; // 20 minutes of work
static const NSInteger kBreakDuration      = 20;      // 20 second break
static const NSInteger kIdleResetThreshold = 5 * 60;  // reset if idle >= 5 minutes

typedef NS_ENUM(NSInteger, EBState) {
    EBStateWorking,
    EBStateOnBreak,
};

@interface AppDelegate ()
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) BreakOverlayController *overlay;
@property (nonatomic, assign) NSInteger secondsRemaining;
@property (nonatomic, assign) EBState state;
@property (nonatomic, assign) BOOL paused;
@property (nonatomic, strong) NSMenuItem *pauseItem;
@property (nonatomic, strong) NSMenuItem *launchAtLoginItem;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.overlay = [[BreakOverlayController alloc] init];

    __weak typeof(self) weakSelf = self;
    self.overlay.onSkip = ^{
        [weakSelf endBreak];
    };

    [self setupStatusItem];

    self.state = EBStateWorking;
    self.secondsRemaining = kWorkInterval;
    [self updateStatusTitle];

    // One tick per second drives the whole app.
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                  target:self
                                                selector:@selector(tick)
                                                userInfo:nil
                                                 repeats:YES];

    // Keep ticking smoothly even while menus are open.
    [[NSRunLoop currentRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)setupStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.font = [NSFont monospacedDigitSystemFontOfSize:13.0
                                                                   weight:NSFontWeightRegular];

    NSMenu *menu = [[NSMenu alloc] init];

    [menu addItemWithTitle:@"Take a break now"
                    action:@selector(takeBreakNow:)
             keyEquivalent:@""].target = self;

    [menu addItemWithTitle:@"Reset timer"
                    action:@selector(resetTimer:)
             keyEquivalent:@""].target = self;

    [menu addItem:[NSMenuItem separatorItem]];

    self.pauseItem = [menu addItemWithTitle:@"Pause"
                                     action:@selector(togglePause:)
                              keyEquivalent:@""];
    self.pauseItem.target = self;

    self.launchAtLoginItem = [menu addItemWithTitle:@"Launch at Login"
                                             action:@selector(toggleLaunchAtLogin:)
                                      keyEquivalent:@""];
    self.launchAtLoginItem.target = self;
    [self updateLaunchAtLoginState];

    [menu addItem:[NSMenuItem separatorItem]];

    [menu addItemWithTitle:@"Quit Eye Break"
                    action:@selector(quit:)
             keyEquivalent:@"q"].target = self;

    self.statusItem.menu = menu;
}

#pragma mark - Timer loop

- (void)tick {
    if (self.paused) {
        return;
    }

    if (self.state == EBStateWorking) {
        // Optional frill: if the user has been idle for a while, keep the
        // timer pinned at full so they get a fresh 20 minutes when they return.
        CFTimeInterval idle = CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateHIDSystemState,
                                                                     kCGAnyInputEventType);
        if (idle >= kIdleResetThreshold) {
            self.secondsRemaining = kWorkInterval;
            [self updateStatusTitle];
            return;
        }

        self.secondsRemaining -= 1;
        if (self.secondsRemaining <= 0) {
            [self startBreak];
            return;
        }
        [self updateStatusTitle];
    } else { // EBStateOnBreak
        // The break only "counts" while you're actually away from the keyboard
        // and mouse (i.e. genuinely looking into the distance). Any input
        // activity restarts the 20s countdown.
        CFTimeInterval idle = CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateHIDSystemState,
                                                                     kCGAnyInputEventType);
        if (idle < 1.0) {
            self.secondsRemaining = kBreakDuration;
            [self.overlay updateSecondsRemaining:self.secondsRemaining];
            return;
        }

        self.secondsRemaining -= 1;
        [self.overlay updateSecondsRemaining:self.secondsRemaining];
        if (self.secondsRemaining <= 0) {
            [self endBreak];
        }
    }
}

#pragma mark - Break lifecycle

- (void)startBreak {
    self.state = EBStateOnBreak;
    self.secondsRemaining = kBreakDuration;
    [self updateStatusTitle];

    // Deliberately do NOT activate/steal focus — the small overlay just floats
    // on top so it won't interrupt a call or whatever you're doing.
    [self.overlay show];
    [self.overlay updateSecondsRemaining:self.secondsRemaining];
}

- (void)endBreak {
    [self.overlay hide];
    self.state = EBStateWorking;
    self.secondsRemaining = kWorkInterval;
    [self updateStatusTitle];
}

#pragma mark - Menu actions

- (void)takeBreakNow:(id)sender {
    if (self.state == EBStateWorking) {
        [self startBreak];
    }
}

- (void)resetTimer:(id)sender {
    if (self.state == EBStateOnBreak) {
        [self endBreak];
    } else {
        self.secondsRemaining = kWorkInterval;
        [self updateStatusTitle];
    }
}

- (void)togglePause:(id)sender {
    self.paused = !self.paused;
    self.pauseItem.title = self.paused ? @"Resume" : @"Pause";
    [self updateStatusTitle];
}

- (void)toggleLaunchAtLogin:(id)sender {
    SMAppService *service = [SMAppService mainAppService];
    NSError *error = nil;
    BOOL ok;
    if (service.status == SMAppServiceStatusEnabled) {
        ok = [service unregisterAndReturnError:&error];
    } else {
        ok = [service registerAndReturnError:&error];
    }
    if (!ok) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Couldn't change Launch at Login";
        alert.informativeText = error.localizedDescription ?: @"Unknown error.";
        [alert runModal];
    }
    [self updateLaunchAtLoginState];
}

- (void)updateLaunchAtLoginState {
    BOOL enabled = ([SMAppService mainAppService].status == SMAppServiceStatusEnabled);
    self.launchAtLoginItem.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)quit:(id)sender {
    [NSApp terminate:nil];
}

#pragma mark - Status bar title

- (void)updateStatusTitle {
    NSString *title;
    if (self.paused) {
        title = @"\U0001F441 --:--"; // pause glyph
    } else if (self.state == EBStateOnBreak) {
        title = @"\U0001F441 Look away";
    } else {
        NSInteger total = MAX(self.secondsRemaining, 0);
        title = [NSString stringWithFormat:@"\U0001F441 %ld:%02ld",
                 (long)(total / 60), (long)(total % 60)];
    }
    self.statusItem.button.title = title;
}

@end
