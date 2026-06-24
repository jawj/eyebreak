#import "BreakOverlayController.h"

static const CGFloat kPanelWidth   = 480.0;
static const CGFloat kPanelHeight  = 56.0;
static const CGFloat kPanelPadding = 16.0;
static const CGFloat kButtonWidth  = 70.0;
static const CGFloat kButtonHeight = 28.0;
static const CGFloat kLabelHeight  = 22.0;
static const CGFloat kTopMargin    = 24.0;

@interface BreakOverlayController ()
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) NSTextField *label;
@end

@implementation BreakOverlayController

- (void)buildPanel {
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, kPanelWidth, kPanelHeight)
                                                styleMask:(NSWindowStyleMaskBorderless |
                                                           NSWindowStyleMaskNonactivatingPanel)
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.level = NSScreenSaverWindowLevel;
    panel.opaque = NO;
    panel.backgroundColor = [NSColor clearColor];
    panel.hasShadow = YES;
    panel.floatingPanel = YES;
    panel.becomesKeyOnlyIfNeeded = YES;
    panel.hidesOnDeactivate = NO;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                               NSWindowCollectionBehaviorFullScreenAuxiliary |
                               NSWindowCollectionBehaviorStationary;
    [panel setReleasedWhenClosed:NO];

    NSView *content = panel.contentView;
    content.wantsLayer = YES;
    content.layer.cornerRadius = 16.0;
    content.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.85].CGColor;

    NSTextField *label = [[NSTextField alloc] initWithFrame:
        NSMakeRect(20.0,
                   (kPanelHeight - kLabelHeight) / 2.0 - 2.0,
                   kPanelWidth - 40.0,
                   kLabelHeight)];
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.alignment = NSTextAlignmentLeft;
    label.textColor = [NSColor whiteColor];
    label.font = [NSFont systemFontOfSize:14.0 weight:NSFontWeightMedium];
    label.cell.usesSingleLineMode = YES;
    self.label = label;
    [content addSubview:label];

    NSButton *skip = [[NSButton alloc] initWithFrame:
        NSMakeRect(kPanelWidth - kPanelPadding - kButtonWidth,
                   (kPanelHeight - kButtonHeight) / 2.0,
                   kButtonWidth,
                   kButtonHeight)];
    skip.bordered = NO;
    skip.wantsLayer = YES;
    skip.layer.cornerRadius = 6.0;
    skip.layer.backgroundColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.18].CGColor;
    skip.target = self;
    skip.action = @selector(skipPressed:);

    NSMutableParagraphStyle *centered = [[NSMutableParagraphStyle alloc] init];
    centered.alignment = NSTextAlignmentCenter;
    skip.attributedTitle = [[NSAttributedString alloc] initWithString:@"Skip"
        attributes:@{ NSForegroundColorAttributeName: [NSColor whiteColor],
                      NSFontAttributeName: [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium],
                      NSParagraphStyleAttributeName: centered }];
    [content addSubview:skip];

    self.panel = panel;
}

- (void)positionPanel {
    NSScreen *screen = [NSScreen mainScreen];
    NSRect visible = screen.visibleFrame;
    CGFloat x = NSMidX(visible) - (kPanelWidth / 2.0);
    CGFloat y = NSMaxY(visible) - kTopMargin - kPanelHeight;
    [self.panel setFrameOrigin:NSMakePoint(x, y)];
}

- (void)show {
    if (!self.panel) [self buildPanel];
    [self positionPanel];
    [self.panel orderFrontRegardless];
}

- (void)skipPressed:(id)sender {
    if (self.onSkip) self.onSkip();
}

- (void)updateSecondsRemaining:(NSInteger)seconds {
    if (seconds < 0) seconds = 0;
    self.label.stringValue = [NSString stringWithFormat:@"\U0001F441 Look into the distance: %lds remaining",
                              (long)seconds];
}

- (void)hide {
    [self.panel orderOut:nil];
}

@end
