#import "VConsoleCompat.h"
#import "VConsolePerformanceViewController.h"
#import "VConsoleMetrics.h"
#import "VConsoleUICommon.h"

#pragma mark - FPS 折线

@interface VConsoleSparklineView : UIView
@property (nonatomic, strong) NSArray<NSNumber *> *samples; // 0..~60 FPS
- (void)setSamples:(NSArray<NSNumber *> *)samples;
@end

@implementation VConsoleSparklineView

- (void)setSamples:(NSArray<NSNumber *> *)samples {
    _samples = samples;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextClearRect(ctx, rect);
    [[UIColor clearColor] setFill];
    CGContextFillRect(ctx, rect);

    NSArray *s = self.samples;
    CGFloat w = rect.size.width, h = rect.size.height;
    CGFloat maxFps = 60.0;

    // 参考网格：30 / 60 FPS
    CGContextSetStrokeColorWithColor(ctx, VConsoleSeparatorColor().CGColor);
    CGContextSetLineWidth(ctx, 0.5);
    for (NSNumber *g in @[@(30.0), @(60.0)]) {
        CGFloat y = h - ([g doubleValue] / maxFps) * h;
        CGContextMoveToPoint(ctx, 0, y);
        CGContextAddLineToPoint(ctx, w, y);
        CGContextStrokePath(ctx);
    }
    if (s.count < 2) return;

    UIBezierPath *path = [UIBezierPath bezierPath];
    for (NSUInteger i = 0; i < s.count; i++) {
        CGFloat x = (CGFloat)i / (CGFloat)(s.count - 1) * w;
        CGFloat fps = MIN([s[i] doubleValue], maxFps);
        CGFloat y = h - (fps / maxFps) * h;
        if (i == 0) [path moveToPoint:CGPointMake(x, y)];
        else [path addLineToPoint:CGPointMake(x, y)];
    }
    CGContextSetStrokeColorWithColor(ctx,
        [UIColor colorWithRed:0.10 green:0.72 blue:0.45 alpha:1.0].CGColor);
    CGContextSetLineWidth(ctx, 1.5);
    CGContextAddPath(ctx, path.CGPath);
    CGContextStrokePath(ctx);
}

@end

#pragma mark - 性能面板

@interface VConsolePerformanceViewController ()
@property (nonatomic, strong, nullable) CADisplayLink *link;
@property (nonatomic, assign) NSInteger frameCount;
@property (nonatomic, assign) CFTimeInterval lastSample;
@property (nonatomic, assign) CFTimeInterval lastUIUpdate;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *fpsSamples;
// UI
@property (nonatomic, strong) UILabel *fpsLabel;
@property (nonatomic, strong) UILabel *fpsHint;
@property (nonatomic, strong) UILabel *cpuLabel;
@property (nonatomic, strong) UILabel *memLabel;
@property (nonatomic, strong) VConsoleSparklineView *sparkline;
@end

@implementation VConsolePerformanceViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = VConsoleBackgroundColor();
    _fpsSamples = [NSMutableArray array];

    _fpsLabel = [self makeMetricLabel];
    _fpsLabel.font = VConsoleScaledFont(42, UIFontWeightBold);
    _fpsLabel.textColor = VConsoleGreenColor();
    _fpsLabel.text = @"--";
    _fpsLabel.textAlignment = NSTextAlignmentCenter;

    _fpsHint = [UILabel new];
    _fpsHint.font = VConsoleScaledFont(12, UIFontWeightRegular);
    _fpsHint.textColor = VConsoleSecondaryLabelColor();
    _fpsHint.text = @"FPS（实时）";
    _fpsHint.textAlignment = NSTextAlignmentCenter;
    _fpsHint.translatesAutoresizingMaskIntoConstraints = NO;

    _cpuLabel = [self makeMetricLabel];
    _cpuLabel.text = @"CPU --";
    _memLabel = [self makeMetricLabel];
    _memLabel.text = @"内存 --";

    UIStackView *topRow = [[UIStackView alloc] initWithArrangedSubviews:@[_cpuLabel, _memLabel]];
    topRow.axis = UILayoutConstraintAxisHorizontal;
    topRow.distribution = UIStackViewDistributionFillEqually;
    topRow.translatesAutoresizingMaskIntoConstraints = NO;

    _sparkline = [[VConsoleSparklineView alloc] init];
    _sparkline.translatesAutoresizingMaskIntoConstraints = NO;
    _sparkline.layer.borderWidth = 0.5;
    _sparkline.layer.borderColor = VConsoleSeparatorColor().CGColor;
    _sparkline.layer.cornerRadius = 6;
    _sparkline.layer.masksToBounds = YES;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_fpsLabel, _fpsHint, topRow, _sparkline]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [stack.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:16].active = YES;
    [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16].active = YES;
    [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16].active = YES;
    [_sparkline.heightAnchor constraintEqualToConstant:120].active = YES;
    [_sparkline.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
}

- (UILabel *)makeMetricLabel {
    UILabel *l = [[UILabel alloc] init];
    l.font = VConsoleScaledFont(15, UIFontWeightMedium);
    l.textColor = VConsoleLabelColor();
    l.translatesAutoresizingMaskIntoConstraints = NO;
    l.textAlignment = NSTextAlignmentCenter;
    return l;
}

#pragma mark - 采样生命周期

/// 仅在面板可见时采样：切到其它 Tab 或关闭面板即停，零开销退出。
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self startMonitoring];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self stopMonitoring];
}

/// refresh 在面板整体弹出时也会触发（覆盖「初始即停留在本 Tab」场景）。
- (void)refresh {
    [self startMonitoring];
}

- (void)startMonitoring {
    if (self.link) return;
    self.frameCount = 0;
    self.lastSample = CACurrentMediaTime();
    self.lastUIUpdate = self.lastSample;
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stopMonitoring {
    [_link invalidate];
    _link = nil;
}

- (void)tick:(CADisplayLink *)link {
    self.frameCount++;
    CFTimeInterval now = link.timestamp;
    CFTimeInterval elapsed = now - self.lastSample;
    if (elapsed >= 1.0) {
        double fps = self.frameCount / elapsed;
        [self.fpsSamples addObject:@(fps)];
        if (self.fpsSamples.count > 60) [self.fpsSamples removeObjectAtIndex:0];
        self.frameCount = 0;
        self.lastSample = now;
    }
    // UI 刷新节流到约 4Hz，避免频繁 layout
    if (now - self.lastUIUpdate >= 0.25) {
        self.lastUIUpdate = now;
        [self updateUI];
    }
}

- (void)updateUI {
    double fps = self.fpsSamples.lastObject ? self.fpsSamples.lastObject.doubleValue : 0;
    self.fpsLabel.text = [NSString stringWithFormat:@"%.0f", fps];
    UIColor *c = (fps >= 50) ? VConsoleGreenColor()
                : (fps >= 30 ? VConsoleOrangeColor() : VConsoleRedColor());
    self.fpsLabel.textColor = c;

    double cpu = VConsoleAppCPUUsage();
    double mem = VConsoleAppMemoryMB();
    self.cpuLabel.text = [NSString stringWithFormat:@"CPU %@", VConsoleFormatPercent(cpu)];
    self.memLabel.text = [NSString stringWithFormat:@"内存 %@",
                          VConsoleFormatBytes((long long)(mem * 1024.0 * 1024.0))];
    [self.sparkline setSamples:[self.fpsSamples copy]];
}

- (void)dealloc {
    [self stopMonitoring];
}

@end
