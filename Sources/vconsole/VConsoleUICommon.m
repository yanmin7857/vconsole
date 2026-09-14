#import "VConsoleCompat.h"
#import "VConsoleUICommon.h"

@implementation VConsoleEmptyStateView {
    UIImageView *_iconView;
    UILabel *_titleLabel;
    UILabel *_subtitleLabel;
}

- (instancetype)initWithSymbol:(NSString *)symbol
                         title:(NSString *)title
                      subtitle:(NSString *)subtitle {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        // 空态不拦截任何点击
        self.userInteractionEnabled = NO;

        UIStackView *stack = [[UIStackView alloc] init];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.alignment = UIStackViewAlignmentCenter;
        stack.spacing = 8;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];

        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.tintColor = VConsoleTertiaryLabelColor();
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [stack addArrangedSubview:_iconView];
        [_iconView.heightAnchor constraintEqualToConstant:40].active = YES;
        [_iconView.widthAnchor constraintEqualToConstant:40].active = YES;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.textColor = VConsoleSecondaryLabelColor();
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        [stack addArrangedSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.textColor = VConsoleTertiaryLabelColor();
        _subtitleLabel.textAlignment = NSTextAlignmentCenter;
        _subtitleLabel.numberOfLines = 0;
        [stack addArrangedSubview:_subtitleLabel];

        // 空态是纯说明性文字，跟随系统字号；用户在设置里改字号后这里也要跟着变
        [self applyScaledFonts];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(vconsoleContentSizeDidChange:)
                                                     name:UIContentSizeCategoryDidChangeNotification
                                                   object:nil];

        [stack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
        [stack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:24].active = YES;
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-24].active = YES;

        [self configureSymbol:symbol title:title subtitle:subtitle];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/// 系统字号变化后重设字体（字号变了行高也要变，UILabel numberOfLines=0 会自己重排）
- (void)vconsoleContentSizeDidChange:(NSNotification *)note {
    [self applyScaledFonts];
}

- (void)applyScaledFonts {
    _titleLabel.font = VConsoleScaledFont(15, UIFontWeightMedium);
    _subtitleLabel.font = VConsoleScaledFont(12, UIFontWeightRegular);
}

- (void)configureSymbol:(NSString *)symbol
                  title:(NSString *)title
               subtitle:(NSString *)subtitle {
    _iconView.image = (symbol.length > 0) ? VConsoleImageNamed(symbol) : nil;
    _iconView.hidden = (symbol.length == 0);
    _titleLabel.text = title;
    _subtitleLabel.text = subtitle;
}

@end

void VConsoleHapticLight(void) {
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
}

void VConsoleHapticWarning(void) {
    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeWarning];
}

void VConsoleHapticSuccess(void) {
    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
}

#pragma mark - 慢请求阈值

NSString * const VConsoleDefaultsKeySlowThresholdMs = @"vcs.slowThresholdMs";
NSString * const VConsoleSlowThresholdDidChangeNotification = @"VConsoleSlowThresholdDidChangeNotification";

/// 默认阈值（毫秒）：与改动前 entryMatchesFilter: 里硬编码的 1000.0 保持一致
static const NSTimeInterval kVConsoleDefaultSlowThresholdMs = 1000.0;

NSTimeInterval VConsoleSlowRequestThresholdMs(void) {
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:VConsoleDefaultsKeySlowThresholdMs];
    // 从未设置过（objectForKey: 返回 nil）时回落到默认值，而不是 doubleForKey: 的 0
    if (![stored respondsToSelector:@selector(doubleValue)]) return kVConsoleDefaultSlowThresholdMs;
    NSTimeInterval ms = [stored doubleValue];
    if (ms <= 0) return kVConsoleDefaultSlowThresholdMs;
    return ms;
}

void VConsoleSetSlowRequestThresholdMs(NSTimeInterval ms) {
    if (ms <= 0) ms = kVConsoleDefaultSlowThresholdMs;
    NSTimeInterval old = VConsoleSlowRequestThresholdMs();
    // 不调用 -synchronize：iOS 12 起已废弃且不必要的（系统会在合适时机落盘）
    [[NSUserDefaults standardUserDefaults] setDouble:ms forKey:VConsoleDefaultsKeySlowThresholdMs];
    // 值没变就不打扰 UI，避免无意义的全量刷新
    if ((ms >= old - 0.5) && (ms <= old + 0.5)) return;
    if ([NSThread isMainThread]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:VConsoleSlowThresholdDidChangeNotification object:nil];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:VConsoleSlowThresholdDidChangeNotification object:nil];
        });
    }
}

#pragma mark - 网络列表排序

NSString * const VConsoleDefaultsKeyNetworkSortMode = @"vcs.networkSortMode";

NSString *VConsoleSortModeTitle(VConsoleNetworkSortMode mode) {
    switch (mode) {
        case VConsoleNetworkSortModeDefault:  return @"默认";
        case VConsoleNetworkSortModeDuration: return @"耗时";
        case VConsoleNetworkSortModeSize:     return @"大小";
        case VConsoleNetworkSortModeStatus:   return @"状态码";
    }
    return @"默认";
}

VConsoleNetworkSortMode VConsoleNetworkSortModeCurrent(void) {
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:VConsoleDefaultsKeyNetworkSortMode];
    // 从未设置过时回落到「默认」（按发生顺序），而不是 integerForKey: 的 0 之外的值
    if (![stored respondsToSelector:@selector(integerValue)]) return VConsoleNetworkSortModeDefault;
    NSInteger v = [stored integerValue];
    if (v < VConsoleNetworkSortModeDefault || v > VConsoleNetworkSortModeStatus) return VConsoleNetworkSortModeDefault;
    return (VConsoleNetworkSortMode)v;
}

void VConsoleSetNetworkSortMode(VConsoleNetworkSortMode mode) {
    if (mode < VConsoleNetworkSortModeDefault || mode > VConsoleNetworkSortModeStatus) mode = VConsoleNetworkSortModeDefault;
    [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:VConsoleDefaultsKeyNetworkSortMode];
}

#pragma mark - 动态字体

UIFont *VConsoleFontForTextStyle(UIFontTextStyle style) {
    return [UIFont preferredFontForTextStyle:style];
}

UIFont *VConsoleScaledFont(CGFloat designSize, UIFontWeight weight) {
    UIFont *base = [UIFont systemFontOfSize:designSize weight:weight];
    if (@available(iOS 11.0, *)) {
        // UIFontMetrics（iOS 11+）：以 Body 曲线缩放我们的设计字号，既不丢设计也不脱离系统字号
        return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:base];
    }
    return base;
}

UIFont *VConsoleScaledMonospaceFont(CGFloat designSize) {
    UIFont *base;
    if (@available(iOS 13.0, *)) {
        // Menlo 缺失时退回系统等宽字体，保证 JSON 对齐不散
        base = [UIFont fontWithName:@"Menlo" size:designSize]
                ?: [UIFont monospacedSystemFontOfSize:designSize weight:UIFontWeightRegular];
    } else {
        // iOS 9/11 回退：Menlo / Courier 缺失则用系统字体兜底
        base = [UIFont fontWithName:@"Menlo" size:designSize]
                ?: [UIFont fontWithName:@"Courier" size:designSize]
                ?: [UIFont systemFontOfSize:designSize];
    }
    if (@available(iOS 11.0, *)) {
        return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:base];
    }
    return base;
}

#pragma mark - 搜索命中高亮

NSAttributedString *VConsoleHighlightedText(NSString *text, NSString *query, UIFont *font, UIColor *color) {
    NSString *safeText = text ?: @"";
    UIFont *safeFont = font ?: [UIFont systemFontOfSize:[UIFont systemFontSize]];
    UIColor *safeColor = color ?: VConsoleLabelColor();

    NSDictionary *baseAttrs = @{NSFontAttributeName: safeFont,
                                NSForegroundColorAttributeName: safeColor};
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] initWithString:safeText
                                                                           attributes:baseAttrs];

    NSString *safeQuery = query ?: @"";
    // 空 query 必须提前返回：rangeOfString: 对空串会命中 location=0 且 length=0，
    // 继续推进会原地打转导致死循环。空 text 也没有可高亮的区间。
    if (safeQuery.length == 0 || safeText.length == 0) return out;

    UIColor *highlight = [VConsoleYellowColor() colorWithAlphaComponent:0.30];
    NSRange searchRange = NSMakeRange(0, safeText.length);
    while (searchRange.length > 0) {
        NSRange hit = [safeText rangeOfString:safeQuery
                                      options:NSCaseInsensitiveSearch
                                        range:searchRange];
        if (hit.location == NSNotFound || hit.length == 0) break;
        [out addAttribute:NSBackgroundColorAttributeName value:highlight range:hit];
        NSUInteger next = NSMaxRange(hit);
        // 命中末尾已到串尾（query 恰为后缀/整个 text）时收尾，避免构造出 location > length 的范围
        if (next >= safeText.length) break;
        searchRange = NSMakeRange(next, safeText.length - next);
    }
    return out;
}
