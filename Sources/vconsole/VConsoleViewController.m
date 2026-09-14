#import "VConsoleCompat.h"
#import "VConsoleViewController.h"
#import "VConsoleController.h"
#import "VConsole.h"
#import "VConsoleLogViewController.h"
#import "VConsoleNetworkViewController.h"
#import "VConsoleStorageViewController.h"
#import "VConsoleSystemViewController.h"
#import "VConsoleSettingsViewController.h"
#import "VConsoleLogger.h"
#import "VConsoleNetworkLogger.h"
#import "VConsoleLogEntry.h"
#import "VConsoleNetworkEntry.h"

static NSString * const kVConsoleTabTitles[] = { @"日志", @"网络", @"存储", @"系统" };

/// 面板最小高度：比例下限与绝对下限取较大者。
///
/// 【为什么下限要设这么高】面板内"固定占用"（列表以外、不随屏高缩放的部分）实测恒为 254pt：
///   header 52
/// + header→tabbar 间隙 10
/// + tabbar 40
/// + tabbar→容器 间隙 8
/// + 搜索框 UISearchBar 64
/// + 日志页筛选 chips 40
/// + 底部工具条 40
/// = 254
/// （容器内那个"滚动到底"按钮是浮在列表之上的，不占高度，不计入。）
/// 因此「列表可用高 ≈ 面板高 − 254」，面板下限必须显著高于 254，否则小屏上列表会被压成 0。
/// 该 254 在 874 / 480 两种视口、且 safeAreaInsets.bottom 不同（34 / 25）下均成立，
/// 即它既不随屏高变化，也不随安全区变化。
///
/// 单靠百分比下限不够：旧值 0.30 在 667 屏上列表直接归零，所以再配一个绝对下限兜底。
/// 绝对下限本身在极短视口下会反过来把面板撑得过大，因此再套一层占比封顶：
///   下限 = max(0.45 * H, min(380, 0.75 * H))
/// H >= 507 时封顶不生效（恒取 380）；只有更短的视口才会被 0.75 * H 压住。
///
/// 实测对照（面板下限 → 列表可用高）：
///   874 屏 → 393.3 → 139.3；667 屏 → 380 → 126；480 视口（iPad 兼容模式）→ 360 → 106；
///   改前 0.30 比例下：874 屏列表 8.3、667 屏列表 0（完全归零）。
static const CGFloat kVConsoleMinPanelHeightFraction = 0.45;
static const CGFloat kVConsoleMinPanelHeightAbsolute = 380.0;
/// 绝对下限在极短视口下的占比封顶，避免面板把小屏几乎占满
static const CGFloat kVConsoleMinPanelHeightAbsoluteCap = 0.75;
static inline CGFloat VConsoleMinPanelHeight(CGFloat H) {
    return MAX(kVConsoleMinPanelHeightFraction * H,
               MIN(kVConsoleMinPanelHeightAbsolute, kVConsoleMinPanelHeightAbsoluteCap * H));
}

@protocol VConsoleGrabberOwner <NSObject>
/// direction: +1 增高 / -1 降低
- (void)adjustPanelHeightWithDirection:(NSInteger)direction;
@end

/// 面板高度调节条（grabber）。实现 UIAccessibilityTraitAdjustable，
/// 让 VoiceOver 用户用上下扫动手势调高度 —— 否则它只能靠拖拽，VoiceOver 完全用不了。
@interface VConsoleGrabberView : UIView
@property (nonatomic, weak, nullable) id<VConsoleGrabberOwner> owner;
@end

@implementation VConsoleGrabberView

- (void)accessibilityIncrement {
    [self.owner adjustPanelHeightWithDirection:1];
}

- (void)accessibilityDecrement {
    [self.owner adjustPanelHeightWithDirection:-1];
}

@end

@interface VConsoleViewController () <UIGestureRecognizerDelegate, VConsoleGrabberOwner>
@property (nonatomic, strong) UIView *dimView;
@property (nonatomic, strong) UIView *panelView;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, strong) UIView *tabBarView;
@property (nonatomic, strong) NSArray<UIButton *> *tabButtons;
@property (nonatomic, strong) NSArray<UILabel *> *tabBadges;
@property (nonatomic, strong) UIView *tabIndicator;
@property (nonatomic, strong) NSLayoutConstraint *tabIndicatorXConstraint;
/// 面板高度调节条（grabber），见 VConsoleGrabberView 定义（可调高度的 adjustable 元素）
@property (nonatomic, strong) VConsoleGrabberView *grabberView;
/// 挂在 panelView 上的下拉关闭手势（需要 delegate 做"是否接管"门禁，故存为属性）
@property (nonatomic, strong) UIPanGestureRecognizer *panelPan;
/// 下拉关闭手势接管期间，被临时禁用自身 pan 的那一个滚动视图（只针对命中的那一个）。
/// weak 的原因：它由 panelView 的子视图树持有，手势期间不可能被释放；万一真被释放，
/// 也是"对象已不存在、无需恢复"，不会留下一个 pan 被永久禁用的列表。
@property (nonatomic, weak) UIScrollView *panCapturedScrollView;
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) NSArray<UIViewController *> *tabs;
@property (nonatomic, strong, nullable) UIViewController *currentTab;
@property (nonatomic, assign) NSInteger selectedTabIndex;
// panelView 自身用约束锚定到 self.view（而非手动 frame），保证子视图 Auto Layout 能拿到正确的几何
@property (nonatomic, strong) NSLayoutConstraint *panelLeadingC;
@property (nonatomic, strong) NSLayoutConstraint *panelTrailingC;
@property (nonatomic, strong) NSLayoutConstraint *panelTopC;
@property (nonatomic, strong) NSLayoutConstraint *panelBottomC;
@property (nonatomic, assign) CGFloat panelBaseTop;
@property (nonatomic, assign) CGFloat panelBaseBottom;
@property (nonatomic, assign) BOOL dragging;
/// 当前是否为"紧凑布局"（底部抽屉贴边）；宽屏为居中卡片。
/// 由 viewDidLayoutSubviews 计算后显式记录，供 grabber 调高度时使用（不靠约束常量反推）。
@property (nonatomic, assign) BOOL panelIsCompactLayout;
// grabber 高度拖拽状态
@property (nonatomic, assign) BOOL heightDragging;
@property (nonatomic, assign) CGFloat grabBaseHeight;
// 角标计数（仅统计未查看的）
@property (nonatomic, assign) NSInteger errorBadge;
@property (nonatomic, assign) NSInteger netBadge;
@end

@implementation VConsoleViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    // 无障碍：面板打开期间让 VoiceOver 忽略面板之外的元素（宿主 App），避免焦点跑到背后
    self.view.accessibilityViewIsModal = YES;

    _dimView = [[UIView alloc] init];
    _dimView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
    _dimView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_dimView];
    [_dimView.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = YES;
    [_dimView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [_dimView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;
    [_dimView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;
    [_dimView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                            action:@selector(dimTapped)]];
    // 无障碍：遮罩只是"点外部关闭"的点击区域，不该被朗读、也不该占用 VoiceOver 焦点遍历
    _dimView.isAccessibilityElement = NO;

    _panelView = [[UIView alloc] init];
    _panelView.backgroundColor = VConsoleSecondaryBackgroundColor();
    _panelView.clipsToBounds = YES;
    _panelView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_panelView];
    // 用约束把 panelView 锚定到 self.view（四边约束，常量在 viewDidLayoutSubviews 里按尺寸类更新）。
    // 这样 panelView 的几何由 Auto Layout 引擎统一管理，子视图（header/tabbar/container）
    // 的约束才能基于正确的 panelView 尺寸求解，避免手动设 frame 导致的子视图尺寸被锁成旧值。
    _panelLeadingC  = [_panelView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor];
    _panelTrailingC = [_panelView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor];
    _panelTopC      = [_panelView.topAnchor      constraintEqualToAnchor:self.view.topAnchor];
    _panelBottomC   = [_panelView.bottomAnchor   constraintEqualToAnchor:self.view.bottomAnchor];
    [NSLayoutConstraint activateConstraints:@[_panelLeadingC, _panelTrailingC, _panelTopC, _panelBottomC]];

    [self buildHeader];
    [self buildTabBar];
    [self buildContainer];

    VConsoleLogViewController *log = [[VConsoleLogViewController alloc] init];
    VConsoleNetworkViewController *net = [[VConsoleNetworkViewController alloc] init];
    VConsoleStorageViewController *store = [[VConsoleStorageViewController alloc] init];
    VConsoleSystemViewController *sys = [[VConsoleSystemViewController alloc] init];
    _tabs = @[log, net, store, sys];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(panelPanned:)];
    // panelView 的后代视图里有日志/网络/存储的 UITableView，直接挂在 panelView 上的 pan
    // 会和列表滚动抢手势。这里挂 delegate，在 gestureRecognizerShouldBegin: 里做门禁：
    // 列表没滚到顶就让列表自己滚，只有「滚到顶 + 向下拖」或「落在外壳区域」才接管。
    pan.delegate = self;
    _panelPan = pan;
    [_panelView addGestureRecognizer:pan];

    // 角标：观察日志错误与网络失败
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onLogAdded:)
                                                 name:VConsoleLoggerDidAddEntryNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onLogCleared)
                                                 name:VConsoleLoggerDidClearNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onNetAdded:)
                                                 name:VConsoleNetworkLoggerDidAddEntryNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onNetCleared)
                                                 name:VConsoleNetworkLoggerDidClearNotification
                                               object:nil];

    [self showTabAtIndex:0];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UI 构建

- (void)buildHeader {
    _headerView = [[UIView alloc] init];
    _headerView.backgroundColor = [UIColor colorWithRed:0.10 green:0.72 blue:0.45 alpha:1.0];
    _headerView.translatesAutoresizingMaskIntoConstraints = NO;
    [_panelView addSubview:_headerView];

    // grabber：拖拽调节面板高度
    _grabberView = [[VConsoleGrabberView alloc] init];
    _grabberView.owner = self;
    _grabberView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.55];
    _grabberView.layer.cornerRadius = 2.5;
    _grabberView.layer.masksToBounds = YES;
    _grabberView.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerView addSubview:_grabberView];
    // 无障碍：可聚焦 + adjustable（上下扫动调高度），并说明怎么用
    _grabberView.isAccessibilityElement = YES;
    _grabberView.accessibilityLabel = @"面板高度";
    _grabberView.accessibilityTraits = UIAccessibilityTraitAdjustable;
    _grabberView.accessibilityHint = @"上下扫动可调整面板高度";
    [_grabberView.widthAnchor constraintEqualToConstant:36].active = YES;
    [_grabberView.heightAnchor constraintEqualToConstant:5].active = YES;
    [_grabberView.centerXAnchor constraintEqualToAnchor:_headerView.centerXAnchor].active = YES;
    [_grabberView.topAnchor constraintEqualToAnchor:_headerView.topAnchor constant:6].active = YES;
    UIPanGestureRecognizer *gpan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                           action:@selector(grabberPanned:)];
    [_grabberView addGestureRecognizer:gpan];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = @"vConsole";
    _titleLabel.textColor = [UIColor whiteColor];
    _titleLabel.font = [UIFont boldSystemFontOfSize:17];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerView addSubview:_titleLabel];
    // 无障碍：作为面板的"标题"，弹入时焦点落点
    _titleLabel.isAccessibilityElement = YES;
    _titleLabel.accessibilityLabel = @"vConsole 调试面板";
    _titleLabel.accessibilityTraits = UIAccessibilityTraitHeader;

    _settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_settingsButton setImage:VConsoleImageNamed(@"gearshape.fill") forState:UIControlStateNormal];
    [_settingsButton setTintColor:[UIColor whiteColor]];
    _settingsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_settingsButton addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [_headerView addSubview:_settingsButton];
    // 无障碍：图标按钮必须补 label，否则 VoiceOver 只能读出空
    _settingsButton.isAccessibilityElement = YES;
    _settingsButton.accessibilityLabel = @"调试面板设置";
    _settingsButton.accessibilityTraits = UIAccessibilityTraitButton;

    _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_closeButton setImage:VConsoleImageNamed(@"xmark") forState:UIControlStateNormal];
    [_closeButton setTintColor:[UIColor whiteColor]];
    _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_closeButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [_headerView addSubview:_closeButton];
    // 无障碍：关闭按钮最关键 —— VoiceOver 用户进得去也必须出得来
    _closeButton.isAccessibilityElement = YES;
    _closeButton.accessibilityLabel = @"关闭调试面板";
    _closeButton.accessibilityTraits = UIAccessibilityTraitButton;

    [_titleLabel.leadingAnchor constraintEqualToAnchor:_headerView.leadingAnchor constant:14].active = YES;
    [_titleLabel.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor constant:6].active = YES;
    [_closeButton.trailingAnchor constraintEqualToAnchor:_headerView.trailingAnchor constant:-10].active = YES;
    [_closeButton.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor constant:6].active = YES;
    [_closeButton.widthAnchor constraintEqualToConstant:36].active = YES;
    [_closeButton.heightAnchor constraintEqualToConstant:36].active = YES;
    [_settingsButton.trailingAnchor constraintEqualToAnchor:_closeButton.leadingAnchor constant:-4].active = YES;
    [_settingsButton.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor constant:6].active = YES;
    [_settingsButton.widthAnchor constraintEqualToConstant:36].active = YES;
    [_settingsButton.heightAnchor constraintEqualToConstant:36].active = YES;
    [_headerView.leadingAnchor constraintEqualToAnchor:_panelView.leadingAnchor].active = YES;
    [_headerView.trailingAnchor constraintEqualToAnchor:_panelView.trailingAnchor].active = YES;
    [_headerView.topAnchor constraintEqualToAnchor:_panelView.topAnchor].active = YES;
    [_headerView.heightAnchor constraintEqualToConstant:52].active = YES;
}

- (void)buildTabBar {
    _tabBarView = [[UIView alloc] init];
    _tabBarView.backgroundColor = VConsoleTertiaryBackgroundColor();
    _tabBarView.translatesAutoresizingMaskIntoConstraints = NO;
    [_panelView addSubview:_tabBarView];
    [_tabBarView.leadingAnchor constraintEqualToAnchor:_panelView.leadingAnchor constant:12].active = YES;
    [_tabBarView.trailingAnchor constraintEqualToAnchor:_panelView.trailingAnchor constant:-12].active = YES;
    [_tabBarView.topAnchor constraintEqualToAnchor:_headerView.bottomAnchor constant:10].active = YES;
    [_tabBarView.heightAnchor constraintEqualToConstant:40].active = YES;
    _tabBarView.layer.cornerRadius = 10;
    _tabBarView.layer.masksToBounds = YES;

    // 等宽布局用 UIStackView（避免 multiplier 约束在非原点容器下计算错误）
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_tabBarView addSubview:stack];
    [stack.topAnchor constraintEqualToAnchor:_tabBarView.topAnchor].active = YES;
    [stack.leadingAnchor constraintEqualToAnchor:_tabBarView.leadingAnchor].active = YES;
    [stack.trailingAnchor constraintEqualToAnchor:_tabBarView.trailingAnchor].active = YES;
    [stack.bottomAnchor constraintEqualToAnchor:_tabBarView.bottomAnchor].active = YES;

    NSMutableArray *buttons = [NSMutableArray array];
    NSMutableArray *badges = [NSMutableArray array];
    for (NSInteger i = 0; i < 4; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.tag = 100 + i;
        [btn setTitle:kVConsoleTabTitles[i] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:14];
        // 无障碍：显式声明为可聚焦元素（UIButton 的 isAccessibilityElement 直读可能为 NO，
        // 显式置 YES 可确保它一定出现在 VoiceOver 的元素树里）
        btn.isAccessibilityElement = YES;
        btn.accessibilityTraits = UIAccessibilityTraitButton; // 选中态在 updateTabSelectionAnimated 里补
        [btn addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:btn];
        [buttons addObject:btn];

        // 角标挂在按钮内部（自动跟随按钮位置），不拦截点击
        UILabel *badge = [[UILabel alloc] init];
        badge.font = [UIFont boldSystemFontOfSize:10];
        badge.textColor = [UIColor whiteColor];
        // 颜色区分语义：0 日志 = 未查看错误（红，与列表里 error 行同色）；
        // 1 网络 = 失败请求（橙，与列表里 4xx/5xx 行同色）。两者含义不同，不能都用红点。
        badge.backgroundColor = (i == 1) ? VConsoleOrangeColor() : VConsoleRedColor();
        badge.textAlignment = NSTextAlignmentCenter;
        badge.layer.cornerRadius = 8;
        badge.layer.masksToBounds = YES;
        badge.hidden = YES;
        badge.userInteractionEnabled = NO;
        badge.isAccessibilityElement = NO; // 未读信息已并入 tab 按钮 label，角标仅视觉提示，避免 VoiceOver 重复朗读
        badge.translatesAutoresizingMaskIntoConstraints = NO;
        [btn addSubview:badge];
        [badge.topAnchor constraintEqualToAnchor:btn.topAnchor constant:3].active = YES;
        [badge.centerXAnchor constraintEqualToAnchor:btn.centerXAnchor constant:16].active = YES;
        [badge.heightAnchor constraintEqualToConstant:16].active = YES;
        [badge.widthAnchor constraintGreaterThanOrEqualToConstant:16].active = YES;
        [badges addObject:badge];
    }
    _tabButtons = [buttons copy];
    _tabBadges = [badges copy];

    // 选中指示条
    _tabIndicator = [[UIView alloc] init];
    _tabIndicator.backgroundColor = [UIColor colorWithRed:0.10 green:0.72 blue:0.45 alpha:1.0];
    _tabIndicator.layer.cornerRadius = 1.5;
    _tabIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [_tabBarView addSubview:_tabIndicator];
    [_tabIndicator.widthAnchor constraintEqualToConstant:24].active = YES;
    [_tabIndicator.heightAnchor constraintEqualToConstant:3].active = YES;
    [_tabIndicator.bottomAnchor constraintEqualToAnchor:_tabBarView.bottomAnchor constant:-2].active = YES;
    // centerX 初始锚到第一个按钮，切换时重建并动画滑动
    _tabIndicatorXConstraint = [_tabIndicator.centerXAnchor constraintEqualToAnchor:_tabButtons[0].centerXAnchor];
    _tabIndicatorXConstraint.active = YES;

    [self updateTabSelectionAnimated:NO];
}

- (void)buildContainer {
    _containerView = [[UIView alloc] init];
    _containerView.translatesAutoresizingMaskIntoConstraints = NO;
    [_panelView addSubview:_containerView];
    [_containerView.leadingAnchor constraintEqualToAnchor:_panelView.leadingAnchor].active = YES;
    [_containerView.trailingAnchor constraintEqualToAnchor:_panelView.trailingAnchor].active = YES;
    [_containerView.topAnchor constraintEqualToAnchor:_tabBarView.bottomAnchor constant:8].active = YES;
    [_containerView.bottomAnchor constraintEqualToAnchor:_panelView.bottomAnchor].active = YES;
}

#pragma mark - Tab 切换

- (void)tabTapped:(UIButton *)sender {
    NSInteger index = sender.tag - 100;
    if (index == self.selectedTabIndex) return;
    UISelectionFeedbackGenerator *gen = [[UISelectionFeedbackGenerator alloc] init];
    [gen selectionChanged];
    [self showTabAtIndex:index];
}

- (void)showTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.tabs.count) return;
    self.selectedTabIndex = index;
    UIViewController *vc = self.tabs[index];
    if (self.currentTab != vc) {
        if (self.currentTab) {
            [self.currentTab willMoveToParentViewController:nil];
            [self.currentTab.view removeFromSuperview];
            [self.currentTab removeFromParentViewController];
        }
        self.currentTab = vc;
        [self addChildViewController:vc];
        vc.view.translatesAutoresizingMaskIntoConstraints = NO;
        [self.containerView addSubview:vc.view];
        [vc.view.topAnchor constraintEqualToAnchor:self.containerView.topAnchor].active = YES;
        [vc.view.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor].active = YES;
        [vc.view.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor].active = YES;
        [vc.view.bottomAnchor constraintEqualToAnchor:self.containerView.bottomAnchor].active = YES;
        [vc didMoveToParentViewController:self];

        // 无障碍：tab 切换完成后把 VoiceOver 焦点移入新 tab 内容区，
        // 否则焦点会停留在 tab 按钮上，VoiceOver 用户无法感知内容已切换。
        // 延到下一 runloop，确保新内容已布局完成、首个可聚焦子视图可聚焦。
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, vc.view);
        });
    }

    // 查看即清除该 tab 的角标
    if (index == 0) { self.errorBadge = 0; }
    if (index == 1) { self.netBadge = 0; }
    [self updateBadges];
    [self updateTabSelectionAnimated:YES];
}

- (void)updateTabSelectionAnimated:(BOOL)animated {
    for (NSInteger i = 0; i < (NSInteger)self.tabButtons.count; i++) {
        UIButton *btn = self.tabButtons[i];
        BOOL selected = (i == self.selectedTabIndex);
        [btn setTitleColor:(selected ? [UIColor colorWithRed:0.08 green:0.60 blue:0.38 alpha:1.0]
                                       : VConsoleSecondaryLabelColor())
                 forState:UIControlStateNormal];
        btn.titleLabel.font = selected ? [UIFont boldSystemFontOfSize:14] : [UIFont systemFontOfSize:14];
        // 无障碍：选中态要体现在 trait 上，否则 VoiceOver 用户分不清当前在哪个 tab
        btn.accessibilityTraits = selected ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected)
                                           : UIAccessibilityTraitButton;
    }
    // 指示条滑动：重建 centerX 约束并动画布局
    if (self.tabIndicatorXConstraint) {
        self.tabIndicatorXConstraint.active = NO;
        [self.tabBarView removeConstraint:self.tabIndicatorXConstraint];
    }
    UIView *target = self.tabButtons[self.selectedTabIndex];
    self.tabIndicatorXConstraint = [self.tabIndicator.centerXAnchor constraintEqualToAnchor:target.centerXAnchor];
    self.tabIndicatorXConstraint.active = YES;
    if (animated) {
        [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            [self.tabBarView layoutIfNeeded];
        } completion:nil];
    }
}

- (void)updateBadges {
    NSInteger counts[4] = {0, 0, 0, 0};
    counts[0] = self.errorBadge;
    counts[1] = self.netBadge;
    for (NSInteger i = 0; i < 4; i++) {
        UILabel *badge = self.tabBadges[i];
        if (counts[i] > 0) {
            badge.hidden = NO;
            badge.text = counts[i] > 99 ? @"99+" : [NSString stringWithFormat:@"%ld", (long)counts[i]];
        } else {
            badge.hidden = YES; // hidden 的视图 VoiceOver 自动跳过，无需额外处理
        }
        // 无障碍：说清"这个点是几条第几类"，而不是只念一个数字
        badge.accessibilityLabel = [self badgeAccessibilityLabelAtIndex:i count:counts[i]];
        self.tabButtons[i].accessibilityLabel = [self tabAccessibilityLabelAtIndex:i count:counts[i]];
    }
}

/// 徽标的无障碍文案（与徽标颜色语义一致：0 错误 / 1 失败请求）
- (NSString *)badgeAccessibilityLabelAtIndex:(NSInteger)index count:(NSInteger)count {
    if (index == 0) return [NSString stringWithFormat:@"%ld 条未查看错误", (long)count];
    if (index == 1) return [NSString stringWithFormat:@"%ld 条失败请求", (long)count];
    return [NSString stringWithFormat:@"%ld 条未读", (long)count];
}

/// Tab 的无障碍文案：无徽标时只报名字，有徽标时顺带说明徽标含义
- (NSString *)tabAccessibilityLabelAtIndex:(NSInteger)index count:(NSInteger)count {
    if (index < 0 || index >= 4) return @"";
    NSString *title = kVConsoleTabTitles[index];
    if (count <= 0) return title;
    if (index == 0) return [NSString stringWithFormat:@"%@，%ld 条未查看错误", title, (long)count];
    if (index == 1) return [NSString stringWithFormat:@"%@，%ld 条失败请求", title, (long)count];
    return [NSString stringWithFormat:@"%@，%ld 条未读", title, (long)count];
}

#pragma mark - 角标通知

/// 通知 object 兼容批量（NSArray）与单条（entry）两种形式
- (NSArray *)entriesFromNotification:(NSNotification *)n class:(Class)cls {
    id obj = n.object;
    if ([obj isKindOfClass:[NSArray class]]) return obj;
    if ([obj isKindOfClass:cls]) return @[obj];
    return nil;
}

- (void)onLogAdded:(NSNotification *)n {
    NSArray *batch = [self entriesFromNotification:n class:[VConsoleLogEntry class]];
    if (!batch) return;
    if (self.selectedTabIndex == 0) return; // 正在看日志页，不算未读
    NSInteger errors = 0;
    for (VConsoleLogEntry *e in batch) {
        if ([e isKindOfClass:[VConsoleLogEntry class]] && e.level == VConsoleLogLevelError) errors++;
    }
    if (errors == 0) return;
    self.errorBadge += errors;
    [self updateBadges];
}

- (void)onLogCleared {
    self.errorBadge = 0;
    [self updateBadges];
}

- (void)onNetAdded:(NSNotification *)n {
    NSArray *batch = [self entriesFromNotification:n class:[VConsoleNetworkEntry class]];
    if (!batch) return;
    if (self.selectedTabIndex == 1) return;
    NSInteger failed = 0;
    for (VConsoleNetworkEntry *e in batch) {
        if (![e isKindOfClass:[VConsoleNetworkEntry class]]) continue;
        if ((e.error.length > 0) || (e.statusCode >= 400)) failed++;
    }
    if (failed == 0) return;
    self.netBadge += failed;
    [self updateBadges];
}

- (void)onNetCleared {
    self.netBadge = 0;
    [self updateBadges];
}

#pragma mark - 布局

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.dragging || self.heightDragging) return;
    CGRect b = self.view.bounds;
    BOOL compact = (b.size.width < 600) ||
                  (self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact);
    // 布局模式在这里算出来就显式记下来，供 grabber 调高度时用。
    // 不要用「panelBaseBottom == 0」之类由结果反推的写法：那是上一次拖拽留下的常量，
    // 宽屏模式下面板被拖到接近满高时 bottom 也趋近 0，会被误判成紧凑模式而把面板贴到底部。
    self.panelIsCompactLayout = compact;
    // 高度取持久化比例（默认 0.80），并夹在安全范围
    CGFloat fraction = [[NSUserDefaults standardUserDefaults] doubleForKey:VConsoleDefaultsKeyPanelHeight];
    if (fraction <= 0.05) fraction = 0.80;
    CGFloat h;
    CGFloat left, right, top, bottom;
    if (compact) {
        // 底部抽屉：左右贴边，底部贴底（下限统一走 VConsoleMinPanelHeight，上限 0.95 不动）
        h = MIN(MAX(fraction * b.size.height, VConsoleMinPanelHeight(b.size.height)), 0.95 * b.size.height);
        h = MIN(h, b.size.height - 20);
        left = 0;
        right = 0;
        bottom = 0;
        top = b.size.height - h;
        _panelView.layer.cornerRadius = 16;
        if (@available(iOS 11.0, *)) {
            _panelView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        }
    } else {
        // 居中卡片：下限同样走 VConsoleMinPanelHeight，上限 MIN(0.90 * H, 720) 保持不动。
        // 上下限关系：H >= 356 时 320 <= MIN(0.90 * H, 720) 恒成立；H 极小时（如 iPad 分屏）
        // MIN(MAX(x, min), max) 会自然收敛到 max，不会出现约束冲突，只是无法同时满足下限。
        h = MIN(MAX(fraction * b.size.height, VConsoleMinPanelHeight(b.size.height)), MIN(0.90 * b.size.height, 720));
        left = (b.size.width - MIN(560, b.size.width - 40)) / 2.0;
        right = left;
        top = (b.size.height - h) / 2.0;
        bottom = (b.size.height - h) / 2.0;
        _panelView.layer.cornerRadius = 16;
        if (@available(iOS 11.0, *)) {
            _panelView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner |
                                              kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
        }
    }
    // 通过约束常量定位 panelView（不再手动设 frame）
    _panelLeadingC.constant  = left;
    _panelTrailingC.constant = right;
    _panelTopC.constant      = top;
    _panelBottomC.constant   = bottom;
    self.panelBaseTop = top;
    self.panelBaseBottom = bottom;
}

#pragma mark - 开合动画

- (void)animatePanelIn {
    if (!self.isViewLoaded) [self loadViewIfNeeded];
    [self.view layoutIfNeeded];
    self.dimView.alpha = 0;
    self.panelView.transform = CGAffineTransformMakeTranslation(0, self.panelView.bounds.size.height + 60);
    [UIView animateWithDuration:0.42
                          delay:0
         usingSpringWithDamping:0.82
          initialSpringVelocity:0.4
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.dimView.alpha = 1;
        self.panelView.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        // 无障碍：面板弹入后把 VoiceOver 焦点移进面板（落在标题上），
        // 否则焦点仍停留在宿主 App，用户根本不知道面板已经打开。
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, self.titleLabel);
    }];
}

- (void)animatePanelOutWithCompletion:(void (^)(void))completion {
    if (!self.isViewLoaded) {
        if (completion) completion();
        return;
    }
    [UIView animateWithDuration:0.22
                          delay:0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self.dimView.alpha = 0;
        self.panelView.transform = CGAffineTransformMakeTranslation(0, self.panelView.bounds.size.height + 60);
    } completion:^(BOOL finished) {
        // 复位，供下次弹入
        self.panelView.transform = CGAffineTransformIdentity;
        // 无障碍：面板收起后通知 VoiceOver 界面已变化，焦点交还给宿主 App
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil);
        if (completion) completion();
    }];
}

#pragma mark - 无障碍：VoiceOver 手势调节面板高度

/// 当前面板高度
- (CGFloat)currentPanelHeight {
    return self.view.bounds.size.height - _panelTopC.constant - _panelBottomC.constant;
}

/// 按新高度更新约束并持久化，规则与 grabber 拖拽保持一致（同一套上下限与布局模式）。
- (void)applyPanelHeight:(CGFloat)targetHeight announce:(BOOL)announce {
    CGFloat H = self.view.bounds.size.height;
    if (H <= 0) return;
    CGFloat h = MIN(MAX(targetHeight, VConsoleMinPanelHeight(H)), 0.95 * H);
    if (self.panelIsCompactLayout) {
        _panelTopC.constant = H - h;
        _panelBottomC.constant = 0;
    } else {
        CGFloat top = (H - h) / 2.0;
        _panelTopC.constant = top;
        _panelBottomC.constant = top;
    }
    // 同步基准值，避免下一次 viewDidLayoutSubviews 把高度弹回去
    self.panelBaseTop = _panelTopC.constant;
    self.panelBaseBottom = _panelBottomC.constant;
    [[NSUserDefaults standardUserDefaults] setDouble:(h / H) forKey:VConsoleDefaultsKeyPanelHeight];
    [self.view layoutIfNeeded];
    if (announce) {
        NSInteger percent = (NSInteger)llround((h / H) * 100.0);
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,
                                        [NSString stringWithFormat:@"面板高度 %ld%%", (long)percent]);
    }
}

/// direction: +1 增高 / -1 降低（由 VConsoleGrabberView 的 increment / decrement 调用）
- (void)adjustPanelHeightWithDirection:(NSInteger)direction {
    CGFloat H = self.view.bounds.size.height;
    if (H <= 0) return;
    CGFloat step = MAX(24.0, 0.06 * H); // 每档约 6%，小屏保底 24pt
    [self applyPanelHeight:([self currentPanelHeight] + direction * step) announce:YES];
}

#pragma mark - 交互

- (void)dimTapped { [self close]; }

- (void)close { [[VConsoleController shared] hide]; }

- (void)openSettings {
    VConsoleSettingsViewController *settings = [[VConsoleSettingsViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settings];
    // 部署目标 iOS 15.0，sheet detents 可直接使用
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    if (@available(iOS 15.0, *)) {
        nav.sheetPresentationController.detents = @[
            [UISheetPresentationControllerDetent mediumDetent],
            [UISheetPresentationControllerDetent largeDetent]
        ];
        nav.sheetPresentationController.prefersGrabberVisible = YES;
    }
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - 手势门禁：下拉关闭 vs 列表滚动

/// 判断某个点是否属于"向下拖"意图（panelPan 自身的速度）。
- (BOOL)panelPanIsDownward {
    if (!self.panelPan) return NO;
    CGPoint v = [self.panelPan velocityInView:self.panelView];
    if (v.y <= 0) return NO;
    CGFloat absY = (v.y < 0) ? -v.y : v.y;
    CGFloat absX = (v.x < 0) ? -v.x : v.x;
    return (absY > absX);
}

/// 从命中的视图向上找最近的 UIScrollView（UITableView / UITextView 等都在其中）。
- (nullable UIScrollView *)scrollViewHitAtPoint:(CGPoint)p {
    UIView *hit = [self.panelView hitTest:p withEvent:nil]; // event 传 nil 安全：仅做几何命中测试
    UIView *cur = hit;
    while (cur && cur != self.panelView) {
        if ([cur isKindOfClass:[UIScrollView class]]) return (UIScrollView *)cur;
        cur = cur.superview;
    }
    return nil;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    // 除 panel 下拉手势外（含 grabber 的高度拖拽手势），一律保持系统默认行为
    if (gestureRecognizer != self.panelPan) return YES;
    if (!self.panelPan) return YES;

    CGPoint p = [gestureRecognizer locationInView:self.panelView];

    // 1) grabber 优先：它自己带 pan 用于调高度，这里让位，否则调高度会同时把面板拖下去
    if (self.grabberView) {
        CGRect grabberInPanel = [self.grabberView convertRect:self.grabberView.bounds toView:self.panelView];
        if (CGRectContainsPoint(grabberInPanel, p)) return NO;
    }

    // 2) 命中顶栏（title/关闭/设置按钮所在区域）→ 无条件接管，保留"抓头部拖走"的直觉
    //    headerView 是 panelView 的子视图，frame 与 p 同一坐标系
    if (self.headerView && CGRectContainsPoint(self.headerView.frame, p)) return YES;

    // 3) 命中滚动视图：没滚到顶就让列表自己滚；滚到顶后只有向下拖才接管（标准 bottom-sheet 行为）
    UIScrollView *sv = [self scrollViewHitAtPoint:p];
    if (sv) {
        if (sv.contentOffset.y > 0.5) return NO;
        return [self panelPanIsDownward];
    }

    // 4) 其它区域（tabbar、按钮间隙等）：同样只在向下拖时接管，避免误触关闭
    return [self panelPanIsDownward];
}

/// 恢复被接管的滚动视图自身的 pan（幂等：nil 时消息发给 nil，安全无副作用）。
- (void)restoreCapturedScrollViewPan {
    self.panCapturedScrollView.panGestureRecognizer.enabled = YES;
    self.panCapturedScrollView = nil;
}

- (void)panelPanned:(UIPanGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        self.dragging = YES;
        // 兜底：理论上上一条手势必然已收尾；万一有残留，先恢复再重新捕获，避免叠加禁用
        if (self.panCapturedScrollView) [self restoreCapturedScrollViewPan];
        // 接管期间只禁用「命中的那一个」滚动视图的 pan：
        // 能走到这里说明列表已滚到顶（见 gestureRecognizerShouldBegin:），此时它的 pan 唯一
        // 能做的事就是橡皮筋回弹，禁掉没有功能损失，却消除了「面板下滑 + 列表橡皮筋」双重位移。
        // 不遍历禁用页面上所有滚动视图 —— 那会误伤别处（例如详情弹层里的滚动视图）。
        UIScrollView *sv = [self scrollViewHitAtPoint:[g locationInView:_panelView]];
        self.panCapturedScrollView = sv;
        sv.panGestureRecognizer.enabled = NO; // sv 为 nil 时消息发送安全
    }
    if (g.state == UIGestureRecognizerStateChanged) {
        CGPoint t = [g translationInView:self.view];
        // 平移 panelView：上下两条边约束常量同步偏移（保持高度不变），并 clamp 防止拖出屏幕
        CGFloat H = self.view.bounds.size.height;
        CGFloat newTop = self.panelBaseTop + t.y;
        newTop = MAX(0, MIN(newTop, H - 60)); // 至少保留 60pt 可见
        _panelTopC.constant = newTop;
        _panelBottomC.constant = self.panelBaseBottom + (newTop - self.panelBaseTop);
        [self.view layoutIfNeeded];
    } else if (g.state == UIGestureRecognizerStateEnded ||
               g.state == UIGestureRecognizerStateCancelled ||
               g.state == UIGestureRecognizerStateFailed) {
        // Failed 必须一并覆盖：手势被系统判定失败时不会走 Ended/Cancelled 分支，
        // 漏掉它会导致列表的 pan 被永久禁用 —— 那比双重位移严重得多。
        CGPoint t = [g translationInView:self.view];
        self.dragging = NO;
        // 先恢复列表的 pan，再决定关闭：否则 close 后 VC 被 dismiss，恢复可能被跳过
        [self restoreCapturedScrollViewPan];
        if (t.y > 100) {
            [self close];
        } else {
            [UIView animateWithDuration:0.22 animations:^{
                // VC 存活期间动画必然完成，显式持有 self 表明这是预期行为
                self->_panelTopC.constant = self.panelBaseTop;
                self->_panelBottomC.constant = self.panelBaseBottom;
                [self.view layoutIfNeeded];
            }];
        }
    }
}

- (void)grabberPanned:(UIPanGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        self.heightDragging = YES;
        self.grabBaseHeight = self.view.bounds.size.height - _panelTopC.constant - _panelBottomC.constant;
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [gen impactOccurred];
    }
    if (g.state == UIGestureRecognizerStateChanged) {
        CGPoint t = [g translationInView:self.view];
        CGFloat H = self.view.bounds.size.height;
        // 上滑增加高度
        CGFloat newH = self.grabBaseHeight - t.y;
        // 布局模式取 viewDidLayoutSubviews 里显式记录的值：
        // 紧凑模式（底部贴边，调高度只动 top）/ 宽屏模式（上下等距居中，调高度两边同时动）。
        // 这里不能用 panelBaseBottom 反推，理由见 viewDidLayoutSubviews 里的注释。
        BOOL compact = self.panelIsCompactLayout;
        // 上滑增加高度（下限统一走 VConsoleMinPanelHeight，上限 0.95 * H 保持不动）
        newH = MIN(MAX(newH, VConsoleMinPanelHeight(H)), 0.95 * H);
        if (compact) {
            _panelTopC.constant = H - newH;
            _panelBottomC.constant = 0;
        } else {
            CGFloat top = (H - newH) / 2.0;
            _panelTopC.constant = top;
            _panelBottomC.constant = top;
        }
        [self.view layoutIfNeeded];
    } else if (g.state == UIGestureRecognizerStateEnded ||
               g.state == UIGestureRecognizerStateCancelled) {
        self.heightDragging = NO;
        CGFloat H = self.view.bounds.size.height;
        CGFloat h = H - _panelTopC.constant - _panelBottomC.constant;
        self.panelBaseTop = _panelTopC.constant;
        self.panelBaseBottom = _panelBottomC.constant;
        // 高度比例持久化（旋转/重启后保持）
        [[NSUserDefaults standardUserDefaults] setDouble:(h / H) forKey:VConsoleDefaultsKeyPanelHeight];
    }
}

- (void)refreshVisible {
    if ([self.currentTab respondsToSelector:@selector(refresh)]) {
        [(id)self.currentTab refresh];
    }
}

#pragma mark - 键盘快捷键（iPad 外接键盘）

- (NSArray<UIKeyCommand *> *)keyCommands {
    NSMutableArray<UIKeyCommand *> *cmds = [NSMutableArray array];
    for (NSInteger i = 0; i < 4; i++) {
        // iOS 13+ 用 title 属性替代已废弃的 discoverabilityTitle
        UIKeyCommand *cmd = [UIKeyCommand keyCommandWithInput:[NSString stringWithFormat:@"%ld", (long)(i + 1)]
                                                 modifierFlags:UIKeyModifierCommand
                                                        action:@selector(kbSelectTab:)];
        if (@available(iOS 13.0, *)) {
            cmd.title = [NSString stringWithFormat:@"切换到%@", kVConsoleTabTitles[i]];
        } else {
            cmd.discoverabilityTitle = [NSString stringWithFormat:@"切换到%@", kVConsoleTabTitles[i]];
        }
        [cmds addObject:cmd];
    }
    UIKeyCommand *esc = [UIKeyCommand keyCommandWithInput:UIKeyInputEscape
                                             modifierFlags:0
                                                    action:@selector(kbClose)];
    if (@available(iOS 13.0, *)) {
        esc.title = @"关闭面板";
    } else {
        esc.discoverabilityTitle = @"关闭面板";
    }
    [cmds addObject:esc];
    UIKeyCommand *find = [UIKeyCommand keyCommandWithInput:@"f"
                                              modifierFlags:UIKeyModifierCommand
                                                     action:@selector(kbFind)];
    if (@available(iOS 13.0, *)) {
        find.title = @"搜索";
    } else {
        find.discoverabilityTitle = @"搜索";
    }
    [cmds addObject:find];
    return cmds;
}

- (void)kbSelectTab:(UIKeyCommand *)cmd {
    NSInteger index = [cmd.input integerValue] - 1;
    if (index >= 0 && index < (NSInteger)self.tabs.count) {
        [self showTabAtIndex:index];
    }
}

- (void)kbClose { [self close]; }

- (void)kbFind {
    if ([self.currentTab respondsToSelector:@selector(focusSearch)]) {
        [(id)self.currentTab focusSearch];
    }
}

@end
