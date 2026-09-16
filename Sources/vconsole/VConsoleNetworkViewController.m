#import "VConsoleCompat.h"
#import "VConsoleNetworkViewController.h"
#import "VConsoleNetworkLogger.h"
#import "VConsoleNetworkEntry.h"
#import "VConsoleDetailViewController.h"
#import "VConsoleJSONFormatter.h"
#import "VConsoleRedactor.h"
#import "VConsoleUICommon.h"
#import "VConsoleToast.h"

/// 刷新合并窗口（秒）：并发请求完成时合并刷新，避免每条记录都 reloadData
static const NSTimeInterval kVConsoleRefreshCoalesceInterval = 0.25;
/// 搜索输入防抖（秒）
static const NSTimeInterval kVConsoleSearchDebounceInterval = 0.15;

@interface VConsoleNetworkViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIScrollView *chipsScroll;
@property (nonatomic, strong) UIStackView *chipStack;
@property (nonatomic, strong) NSArray<UIButton *> *chipButtons;
@property (nonatomic, strong) UIButton *clearButton;
@property (nonatomic, strong) UIButton *sortButton;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) VConsoleEmptyStateView *emptyView;
@property (nonatomic, strong) NSArray<VConsoleNetworkEntry *> *entries;
@property (nonatomic, copy) NSString *searchText;
/// 筛选模式：0 全部 1 仅失败 2 慢请求（阈值见 VConsoleSlowRequestThresholdMs()，设置页可调）
@property (nonatomic, assign) NSInteger filterMode;
/// 列表排序方式（持久化在 NSUserDefaults，默认按发生顺序）
@property (nonatomic, assign) VConsoleNetworkSortMode sortMode;
@property (nonatomic, assign) BOOL refreshPending;
@property (nonatomic, strong, nullable) dispatch_block_t searchDebounce;
/// 搜索结果导航：上一个/下一个匹配 + 当前计数（搜索态显示在底部操作栏）
@property (nonatomic, strong) UIButton *matchPrevButton;
@property (nonatomic, strong) UIButton *matchNextButton;
@property (nonatomic, strong) UILabel *matchCountLabel;
/// 当前高亮的匹配项（在过滤后 self.entries 中的下标）；-1 表示无
@property (nonatomic, assign) NSInteger currentMatchRow;
/// 搜索词从空变非空时，下一次 refresh 后自动滚动到首条匹配
@property (nonatomic, assign) BOOL scrollToCurrentOnNextUpdate;
@property (nonatomic, strong) NSDateFormatter *timeFormatter;
@end

@implementation VConsoleNetworkViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = VConsoleBackgroundColor();

    // NSDateFormatter 创建昂贵，全局只建一次复用（精确到毫秒，便于排查请求时序）
    _timeFormatter = [[NSDateFormatter alloc] init];
    _timeFormatter.dateFormat = @"HH:mm:ss.SSS";
    // 排序方式跨启动保留
    _sortMode = VConsoleNetworkSortModeCurrent();

    // 搜索栏
    _searchBar = [[UISearchBar alloc] init];
    _searchBar.placeholder = @"搜索 URL / 方法";
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.delegate = self;
    _searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_searchBar];

    // 筛选 chips（水平滚动）：全部 / 仅失败 / 慢请求
    _chipsScroll = [[UIScrollView alloc] init];
    _chipsScroll.showsHorizontalScrollIndicator = NO;
    _chipsScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_chipsScroll];

    _chipStack = [[UIStackView alloc] init];
    _chipStack.axis = UILayoutConstraintAxisHorizontal;
    _chipStack.spacing = 8;
    _chipStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_chipsScroll addSubview:_chipStack];
    if (@available(iOS 11.0, *)) {
        [_chipStack.leadingAnchor constraintEqualToAnchor:_chipsScroll.contentLayoutGuide.leadingAnchor constant:12].active = YES;
        [_chipStack.trailingAnchor constraintLessThanOrEqualToAnchor:_chipsScroll.contentLayoutGuide.trailingAnchor constant:-12].active = YES;
        [_chipStack.centerYAnchor constraintEqualToAnchor:_chipsScroll.frameLayoutGuide.centerYAnchor].active = YES;
    } else {
        // iOS 9 无 contentLayoutGuide/frameLayoutGuide：直接相对 scrollView 边缘布局
        [_chipStack.leadingAnchor constraintEqualToAnchor:_chipsScroll.leadingAnchor constant:12].active = YES;
        [_chipStack.trailingAnchor constraintLessThanOrEqualToAnchor:_chipsScroll.trailingAnchor constant:-12].active = YES;
        [_chipStack.centerYAnchor constraintEqualToAnchor:_chipsScroll.centerYAnchor].active = YES;
    }

    // 列表
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    // 开启自动行高：原来是系统默认固定行高（44），字号一大 URL 就被截断。
    // 给估算值是为了避免滚动中反复修正 contentSize 造成跳动。
    _tableView.estimatedRowHeight = 44;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    [self.view addSubview:_tableView];

    // 底部操作栏
    UIView *bar = [[UIView alloc] init];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = VConsoleTertiaryBackgroundColor();
    [self.view addSubview:bar];

    _countLabel = [[UILabel alloc] init];
    // 刻意不跟随动态字体：底部 40pt 操作栏横向空间固定，跟随会与右侧按钮撞约束。
    // 参见 VConsoleUICommon.h 的例外清单。
    _countLabel.font = [UIFont systemFontOfSize:12];
    _countLabel.textColor = VConsoleSecondaryLabelColor();
    _countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:_countLabel];

    // 排序按钮：放在「清空记录」左侧，标题显示当前排序方式
    _sortButton = [UIButton buttonWithType:UIButtonTypeSystem];
    // 同 countLabel：操作栏内文字刻意不跟随动态字体
    _sortButton.titleLabel.font = [UIFont systemFontOfSize:12];
    _sortButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_sortButton addTarget:self action:@selector(sortTapped) forControlEvents:UIControlEventTouchUpInside];
    // 无障碍：排序按钮，label 随当前排序方式更新（见 updateSortButtonTitle）
    _sortButton.isAccessibilityElement = YES;
    _sortButton.accessibilityTraits = UIAccessibilityTraitButton;
    _sortButton.accessibilityHint = @"轻点选择列表排序方式";
    [bar addSubview:_sortButton];
    [self updateSortButtonTitle];

    _clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_clearButton setTitle:@"清空记录" forState:UIControlStateNormal];
    _clearButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_clearButton addTarget:self action:@selector(clear) forControlEvents:UIControlEventTouchUpInside];
    // 无障碍：清空按钮
    _clearButton.isAccessibilityElement = YES;
    _clearButton.accessibilityLabel = @"清空网络记录";
    _clearButton.accessibilityHint = @"删除全部网络记录，操作不可撤销";
    _clearButton.accessibilityTraits = UIAccessibilityTraitButton;
    [bar addSubview:_clearButton];

    // 搜索结果导航（上/下一个匹配）：搜索态显示在底部操作栏右侧
    _matchPrevButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_matchPrevButton setTitle:@"‹" forState:UIControlStateNormal];
    _matchPrevButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    _matchPrevButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_matchPrevButton addTarget:self action:@selector(gotoMatchPrev) forControlEvents:UIControlEventTouchUpInside];
    _matchPrevButton.hidden = YES;
    _matchPrevButton.isAccessibilityElement = YES;
    _matchPrevButton.accessibilityLabel = @"上一个匹配";
    _matchPrevButton.accessibilityHint = @"轻点跳到上一条匹配结果";
    _matchPrevButton.accessibilityTraits = UIAccessibilityTraitButton;
    [self.view addSubview:_matchPrevButton];

    _matchNextButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_matchNextButton setTitle:@"›" forState:UIControlStateNormal];
    _matchNextButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    _matchNextButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_matchNextButton addTarget:self action:@selector(gotoMatchNext) forControlEvents:UIControlEventTouchUpInside];
    _matchNextButton.hidden = YES;
    _matchNextButton.isAccessibilityElement = YES;
    _matchNextButton.accessibilityLabel = @"下一个匹配";
    _matchNextButton.accessibilityHint = @"轻点跳到下一条匹配结果";
    _matchNextButton.accessibilityTraits = UIAccessibilityTraitButton;
    [self.view addSubview:_matchNextButton];

    _matchCountLabel = [[UILabel alloc] init];
    _matchCountLabel.font = [UIFont systemFontOfSize:12];
    _matchCountLabel.textColor = VConsoleSecondaryLabelColor();
    _matchCountLabel.textAlignment = NSTextAlignmentCenter;
    _matchCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _matchCountLabel.hidden = YES;
    _matchCountLabel.isAccessibilityElement = YES;
    _matchCountLabel.accessibilityLabel = @"匹配位置";
    [self.view addSubview:_matchCountLabel];

    // 空态（覆盖在列表区域中央，不拦截点击）
    _emptyView = [[VConsoleEmptyStateView alloc] initWithSymbol:@"network"
                                                      title:@"暂无网络记录"
                                                   subtitle:@"被捕获的 HTTP 请求会显示在这里"];
    _emptyView.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyView.hidden = YES;
    [self.view addSubview:_emptyView];

    // 约束
    [_searchBar.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = YES;
    [_searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [_searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;
    [_chipsScroll.topAnchor constraintEqualToAnchor:_searchBar.bottomAnchor].active = YES;
    [_chipsScroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [_chipsScroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;
    [_chipsScroll.heightAnchor constraintEqualToConstant:40].active = YES;
    [_tableView.topAnchor constraintEqualToAnchor:_chipsScroll.bottomAnchor].active = YES;
    [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;
    [_tableView.bottomAnchor constraintEqualToAnchor:bar.topAnchor].active = YES;
    [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;
    [bar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;
    [bar.heightAnchor constraintEqualToConstant:40].active = YES;
    [_countLabel.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:12].active = YES;
    [_countLabel.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor].active = YES;
    // 计数标签不得压到排序按钮上（排序名长度会变）
    [_countLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_sortButton.leadingAnchor constant:-8].active = YES;
    [_sortButton.trailingAnchor constraintEqualToAnchor:_clearButton.leadingAnchor constant:-12].active = YES;
    [_sortButton.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor].active = YES;
    [_clearButton.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-12].active = YES;
    [_clearButton.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor].active = YES;
    [_emptyView.centerXAnchor constraintEqualToAnchor:_tableView.centerXAnchor].active = YES;
    [_emptyView.centerYAnchor constraintEqualToAnchor:_tableView.centerYAnchor].active = YES;

    // 通知已由 VConsoleNetworkLogger 派发到主线程，这里直接处理（含节流合并）
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onChanged)
                                                 name:VConsoleNetworkLoggerDidAddEntryNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onChanged)
                                                 name:VConsoleNetworkLoggerDidClearNotification
                                               object:nil];
    // 阈值在设置页改掉后要立刻重绘 chip 标题与慢请求标记
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onSlowThresholdChanged:)
                                                 name:VConsoleSlowThresholdDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onToggle:)
                                                 name:VConsoleNetworkLoggerDidToggleNotification
                                               object:nil];
    // 系统字号变化：行高 automaticDimension，必须 reloadData 才会按新字号重算
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onContentSizeChanged:)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];

    // 搜索结果导航：底部操作栏右侧（排序按钮左侧）的 ‹ k/N ›
    // 注意：网络操作栏比日志多一个「排序」按钮，故锚到排序按钮左侧而非清空按钮，
    // 否则计数与 › 会被排序按钮压住（实测）。
    [_matchCountLabel.trailingAnchor constraintEqualToAnchor:_sortButton.leadingAnchor constant:-10].active = YES;
    [_matchCountLabel.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor].active = YES;
    [_matchCountLabel.widthAnchor constraintGreaterThanOrEqualToConstant:42].active = YES;
    [_matchNextButton.trailingAnchor constraintEqualToAnchor:_matchCountLabel.leadingAnchor constant:-2].active = YES;
    [_matchNextButton.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor].active = YES;
    [_matchPrevButton.trailingAnchor constraintEqualToAnchor:_matchNextButton.leadingAnchor constant:-2].active = YES;
    [_matchPrevButton.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor].active = YES;

    [self buildChips];
    [self refresh];
}

/// 阈值变更：chip 标题与列表标记都依赖它，不刷新的话 chip 会「说谎」
/// （显示 >1000ms 却按 3000ms 过滤）
- (void)onSlowThresholdChanged:(NSNotification *)n {
    [self updateChipAppearance];
    [self refresh];
}

- (void)onContentSizeChanged:(NSNotification *)n {
    [self updateChipAppearance];
    [_tableView reloadData];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

#pragma mark - 筛选

- (void)buildChips {
    // 第三个 chip 的标题由 updateChipAppearance 按当前阈值拼出（这里只是占位）
    NSArray<NSString *> *titles = @[@"全部", @"仅失败", @"慢请求"];
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.tag = i;
        // 刻意不跟随动态字体：chip 是固定 26pt 高的圆角胶囊。
        // 参见 VConsoleUICommon.h 里「动态字体的例外清单」。
        b.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        b.layer.cornerRadius = 13;
        b.layer.masksToBounds = YES;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        b.contentEdgeInsets = UIEdgeInsetsMake(5, 12, 5, 12);
#pragma clang diagnostic pop
        [b setTitle:titles[i] forState:UIControlStateNormal];
        [b addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
        b.translatesAutoresizingMaskIntoConstraints = NO;
        // 无障碍：筛选标签，显式声明可聚焦并给出提示
        b.isAccessibilityElement = YES;
        b.accessibilityHint = @"轻点筛选网络记录";
        [b.heightAnchor constraintEqualToConstant:26].active = YES;
        [_chipStack addArrangedSubview:b];
        [buttons addObject:b];
    }
    _chipButtons = [buttons copy];
    [self updateChipAppearance];
}

- (void)chipTapped:(UIButton *)sender {
    if (self.filterMode == sender.tag) return;
    self.filterMode = sender.tag;
    VConsoleHapticLight();
    [self updateChipAppearance];
    [self refresh];
}

- (void)updateChipAppearance {
    for (UIButton *b in self.chipButtons) {
        // 阈值可在设置页改，chip 标题跟着变，避免标签写死 ">1s" 与实际阈值不一致
        if (b.tag == 2) {
            [b setTitle:[NSString stringWithFormat:@"慢请求 >%.0fms", VConsoleSlowRequestThresholdMs()]
                forState:UIControlStateNormal];
        }
        BOOL selected = (b.tag == self.filterMode);
        if (selected) {
            b.backgroundColor = [UIColor colorWithRed:0.10 green:0.72 blue:0.45 alpha:1.0];
            [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        } else {
            b.backgroundColor = VConsoleSecondarySystemFillColor();
            [b setTitleColor:VConsoleLabelColor() forState:UIControlStateNormal];
        }
        // 无障碍：选中的筛选标签加 Selected trait；label 用当前标题（慢请求阈值标题会变）
        b.accessibilityLabel = [b titleForState:UIControlStateNormal];
        b.accessibilityTraits = selected ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected)
                                         : UIAccessibilityTraitButton;
    }
}

/// 单条记录是否命中当前筛选模式
- (BOOL)entryMatchesFilter:(VConsoleNetworkEntry *)e {
    switch (self.filterMode) {
        case 1: return (e.error.length > 0) || (e.statusCode >= 400);
        case 2: return (e.durationMs > VConsoleSlowRequestThresholdMs());
        default: return YES;
    }
}

- (void)onToggle:(NSNotification *)n {
    [self refresh];
}

- (NSArray<VConsoleNetworkEntry *> *)filteredFrom:(NSArray<VConsoleNetworkEntry *> *)all {
    BOOL hasFilter = (self.filterMode > 0 || self.searchText.length > 0);
    if (!hasFilter) return all;
    NSString *q = self.searchText;
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:all.count];
    for (VConsoleNetworkEntry *e in all) {
        if (![self entryMatchesFilter:e]) continue;
        if (q.length > 0 &&
            [e.url rangeOfString:q options:NSCaseInsensitiveSearch].location == NSNotFound &&
            [e.method rangeOfString:q options:NSCaseInsensitiveSearch].location == NSNotFound &&
            (e.error.length == 0 || [e.error rangeOfString:q options:NSCaseInsensitiveSearch].location == NSNotFound)) continue;
        [out addObject:e];
    }
    return out;
}

#pragma mark - 排序

- (void)updateSortButtonTitle {
    [_sortButton setTitle:[NSString stringWithFormat:@"排序：%@", VConsoleSortModeTitle(self.sortMode)]
                 forState:UIControlStateNormal];
    // 无障碍：把当前生效的排序方式并入口播 label，VoiceOver 用户无需先点开才知道
    _sortButton.accessibilityLabel = [NSString stringWithFormat:@"排序方式，当前%@", VConsoleSortModeTitle(self.sortMode)];
}

/// 排序只作用于展示副本：VConsoleNetworkLogger 的数组是共享数据源，
/// 就地排序会污染「共 N 条」计数和其它消费方。
- (NSArray<VConsoleNetworkEntry *> *)sortedFrom:(NSArray<VConsoleNetworkEntry *> *)list {
    VConsoleNetworkSortMode mode = self.sortMode;
    if (mode == VConsoleNetworkSortModeDefault || list.count < 2) return list;
    // NSSortStable：同键值的记录保持原有发生顺序，切换排序时不会把等价项打乱
    return [list sortedArrayWithOptions:NSSortStable
                       usingComparator:^NSComparisonResult(VConsoleNetworkEntry *a, VConsoleNetworkEntry *b) {
        // 三个分支都是「降序」：大的排前面
        switch (mode) {
            case VConsoleNetworkSortModeDuration: {
                if (a.durationMs > b.durationMs) return NSOrderedAscending;
                if (a.durationMs < b.durationMs) return NSOrderedDescending;
                return NSOrderedSame;
            }
            case VConsoleNetworkSortModeSize: {
                if (a.responseSize > b.responseSize) return NSOrderedAscending;
                if (a.responseSize < b.responseSize) return NSOrderedDescending;
                return NSOrderedSame;
            }
            case VConsoleNetworkSortModeStatus: {
                if (a.statusCode > b.statusCode) return NSOrderedAscending;
                if (a.statusCode < b.statusCode) return NSOrderedDescending;
                return NSOrderedSame;
            }
            case VConsoleNetworkSortModeDefault:
                return NSOrderedSame;
        }
        return NSOrderedSame;
    }];
}

/// 排序方式选择：用 alert 而不是 actionSheet，省掉 iPad 上 popover 锚点的一堆麻烦
- (void)sortTapped {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"排序方式"
                                                               message:nil
                                                        preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    for (NSInteger i = VConsoleNetworkSortModeDefault; i <= VConsoleNetworkSortModeStatus; i++) {
        VConsoleNetworkSortMode m = (VConsoleNetworkSortMode)i;
        BOOL isCurrent = (m == self.sortMode);
        NSString *title = [NSString stringWithFormat:@"%@%@", VConsoleSortModeTitle(m), isCurrent ? @" ✓" : @""];
        [ac addAction:[UIAlertAction actionWithTitle:title
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
            if (m == weakSelf.sortMode) return;
            weakSelf.sortMode = m;
            VConsoleSetNetworkSortMode(m);
            VConsoleHapticLight();
            [weakSelf updateSortButtonTitle];
            [weakSelf refresh];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - 刷新

- (void)onChanged {
    if (self.refreshPending) return;
    self.refreshPending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kVConsoleRefreshCoalesceInterval * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.refreshPending = NO;
        [self refresh];
    });
}

- (void)refresh {
    NSArray *all = [[VConsoleNetworkLogger shared] entries];
    BOOL filtered = (self.filterMode > 0 || self.searchText.length > 0);
    BOOL sorted = (self.sortMode != VConsoleNetworkSortModeDefault);
    NSArray *shown = filtered ? [self filteredFrom:all] : all;
    shown = [self sortedFrom:shown];
    NSUInteger oldCount = self.entries.count;
    NSUInteger newCount = shown.count;
    BOOL wasAtBottom = [self isTableViewAtBottom];

    self.entries = shown;
    if (filtered) {
        _countLabel.text = [NSString stringWithFormat:@"匹配 %lu / 共 %lu 条",
                            (unsigned long)newCount, (unsigned long)all.count];
    } else {
        _countLabel.text = [NSString stringWithFormat:@"共 %lu 条", (unsigned long)newCount];
    }

    // 过滤态下行号不对应，全量刷新；未过滤且未排序时记录只追加，增量插入即可。
    // 排序后新增一条会插到中间而不是末尾，行号同样不再对应，必须全量刷新，
    // 否则会出现顺序错乱甚至插入越界。
    BOOL needsFullReload = (filtered || sorted);
    if (!needsFullReload && newCount > oldCount && oldCount > 0) {
        NSMutableArray *paths = [NSMutableArray array];
        for (NSUInteger i = oldCount; i < newCount; i++) {
            [paths addObject:[NSIndexPath indexPathForRow:i inSection:0]];
        }
        [_tableView beginUpdates];
        [_tableView insertRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationNone];
        [_tableView endUpdates];
    } else {
        [_tableView reloadData];
    }

    // 空态：抓包关闭时给出引导，而不是误导性的「暂无记录」
    if (newCount > 0) {
        self.emptyView.hidden = YES;
    } else if (![[VConsoleNetworkLogger shared] isEnabled]) {
        [self.emptyView configureSymbol:@"network.slash"
                                  title:@"网络抓包已关闭"
                               subtitle:@"在「设置 → 网络抓包」中开启后即可捕获请求"];
        self.emptyView.hidden = NO;
    } else if (filtered) {
        [self.emptyView configureSymbol:@"magnifyingglass"
                                  title:@"无匹配结果"
                               subtitle:@"换个 URL 关键词，或点击「全部」清除筛选"];
        self.emptyView.hidden = NO;
    } else {
        [self.emptyView configureSymbol:@"network"
                                  title:@"暂无网络记录"
                               subtitle:@"被捕获的 HTTP 请求会显示在这里"];
        self.emptyView.hidden = NO;
    }

    if (wasAtBottom && newCount > 0) {
        [_tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:newCount - 1 inSection:0]
                          atScrollPosition:UITableViewScrollPositionBottom
                                  animated:NO];
    }

    [self updateMatchNavigation];
}

- (BOOL)isTableViewAtBottom {
    CGFloat offset = _tableView.contentOffset.y;
    CGFloat contentH = _tableView.contentSize.height;
    CGFloat frameH = _tableView.frame.size.height;
    if (contentH <= frameH) return YES;
    return (contentH - offset - frameH) < 60;
}

- (void)clear {
    // 条数取未过滤的全量：清空会删掉筛选之外的记录，提示必须是真实删除量
    NSUInteger total = [[VConsoleNetworkLogger shared] entries].count;
    if (total == 0) {
        [VConsoleToast showInView:self.view message:@"暂无记录可清空"];
        return;
    }
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"清空网络记录？"
                                                                message:[NSString stringWithFormat:@"将删除 %lu 条网络记录，此操作不可撤销。", (unsigned long)total]
                                                         preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"清空"
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *action) {
        VConsoleHapticWarning();
        [[VConsoleNetworkLogger shared] clear];
        [VConsoleToast showInView:weakSelf.view message:@"已清空网络记录"];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - 搜索

- (void)focusSearch {
    [self.searchBar becomeFirstResponder];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.searchText = searchText;
    // 每次输入都从首条匹配重新开始导航；首次出现搜索词时滚动到首条
    self.currentMatchRow = 0;
    self.scrollToCurrentOnNextUpdate = (searchText.length > 0);
    // 有输入时才显示「取消」：空搜索框常驻一个取消按钮既占地方又无意义。
    // 之前从未设置过 showsCancelButton，导致下面的 searchBarCancelButtonClicked: 永不触发。
    searchBar.showsCancelButton = (searchText.length > 0);
    // 输入防抖：避免每个字符都全量过滤刷新
    if (self.searchDebounce) {
        dispatch_block_cancel(self.searchDebounce);
    }
    self.searchDebounce = dispatch_block_create(0, ^{
        [self refresh];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kVConsoleSearchDebounceInterval * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), self.searchDebounce);
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = @"";
    self.searchText = @"";
    searchBar.showsCancelButton = NO;
    [searchBar resignFirstResponder];
    [self refresh];
}

#pragma mark - 搜索结果导航

- (void)updateMatchNavigation {
    BOOL searching = (self.searchText.length > 0);
    NSUInteger count = self.entries.count;
    self.matchPrevButton.hidden = !searching;
    self.matchNextButton.hidden = !searching;
    self.matchCountLabel.hidden = !searching;
    if (!searching || count == 0) {
        self.currentMatchRow = -1;
        self.scrollToCurrentOnNextUpdate = NO;
        return;
    }
    if (self.currentMatchRow < 0 || self.currentMatchRow >= (NSInteger)count) {
        self.currentMatchRow = 0;
    }
    self.matchCountLabel.text = [NSString stringWithFormat:@"%ld/%lu",
                                 (long)(self.currentMatchRow + 1), (unsigned long)count];
    self.matchPrevButton.enabled = (self.currentMatchRow > 0);
    self.matchNextButton.enabled = (self.currentMatchRow < (NSInteger)count - 1);
    if (self.scrollToCurrentOnNextUpdate) {
        self.scrollToCurrentOnNextUpdate = NO;
        [self scrollToCurrentMatchAnimated:NO];
    } else if (self.currentMatchRow >= 0 && (NSUInteger)self.currentMatchRow < count) {
        // 仅刷新当前行标记（不滚动），避免新日志到达时把浏览位置拉走
        [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:self.currentMatchRow inSection:0]]
                              withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (void)scrollToCurrentMatchAnimated:(BOOL)animated {
    if (self.currentMatchRow < 0 || (NSUInteger)self.currentMatchRow >= self.entries.count) return;
    NSIndexPath *ip = [NSIndexPath indexPathForRow:self.currentMatchRow inSection:0];
    [self.tableView scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:animated];
    [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)gotoMatch:(NSInteger)delta {
    if (self.searchText.length == 0 || self.entries.count == 0) return;
    NSInteger count = (NSInteger)self.entries.count;
    NSInteger next = (self.currentMatchRow < 0) ? 0 : MAX(0, MIN(count - 1, self.currentMatchRow + delta));
    if (next == self.currentMatchRow) return;
    NSInteger old = self.currentMatchRow;
    self.currentMatchRow = next;
    [self updateMatchNavigation];
    // 旧行必须一并刷新：否则它残留的「当前匹配」标记会累积成多行高亮（实测踩过）
    NSMutableArray<NSIndexPath *> *rows = [NSMutableArray array];
    if (old >= 0 && old < count) [rows addObject:[NSIndexPath indexPathForRow:old inSection:0]];
    [rows addObject:[NSIndexPath indexPathForRow:next inSection:0]];
    [self.tableView reloadRowsAtIndexPaths:rows withRowAnimation:UITableViewRowAnimationNone];
    VConsoleHapticLight();
    [self scrollToCurrentMatchAnimated:YES];
}

- (void)gotoMatchNext { [self gotoMatch:1]; }
- (void)gotoMatchPrev { [self gotoMatch:-1]; }

/// 面板容器 ⌘G / ⇧⌘G 快捷键转发入口
- (void)nextMatch { [self gotoMatchNext]; }
- (void)prevMatch { [self gotoMatchPrev]; }

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.entries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"netcell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
        // 不设 numberOfLines 上限：字号调到最大时 2 行会把 URL 拦腰截断
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.textColor = VConsoleSecondaryLabelColor();
    }
    VConsoleNetworkEntry *e = self.entries[indexPath.row];
    NSString *title = [NSString stringWithFormat:@"%@ %@", e.method, e.url];
    UIFont *titleFont = VConsoleScaledFont(12, UIFontWeightRegular);
    cell.textLabel.font = titleFont;
    // 字体必须每次都设：系统字号变化后复用池里的旧 cell 还带着旧字号，
    // reloadData 不会重走创建分支。
    cell.detailTextLabel.font = VConsoleScaledFont(11, UIFontWeightRegular);
    // 有搜索词时高亮命中的 URL/方法片段；无搜索词先置 nil 再赋 text，防止复用残留高亮。
    // 只处理 textLabel（URL 行），detailTextLabel 保持状态色语义不变。
    NSString *q = (self.searchText.length > 0) ? self.searchText : nil;
    if (q) {
        cell.textLabel.attributedText = VConsoleHighlightedText(title, q, titleFont, VConsoleLabelColor());
    } else {
        cell.textLabel.attributedText = nil;
        cell.textLabel.text = title;
    }
    // 慢请求标记：出错的行已经是红色文案，不重复叠加图标，避免信息打架
    BOOL slow = (e.durationMs > VConsoleSlowRequestThresholdMs()) && (e.error.length == 0);
    if (slow) {
        // SF Symbol 默认是 automatic 渲染模式，显式转 AlwaysTemplate 才能保证 tintColor 生效
        cell.imageView.image = [VConsoleImageNamed(@"tortoise") imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        cell.imageView.tintColor = VConsoleOrangeColor();
    } else {
        // 复用时必须清空，否则非慢请求行会挂上别人的图标
        cell.imageView.image = nil;
    }
    // Mock 命中紫色、H5（WKWebView JS 请求）青色、失败红色、4xx/5xx 橙色、正常绿色
    UIColor *statusColor = e.mocked ? VConsolePurpleColor() :
        (e.fromWeb && !e.error ? VConsoleTealColor() :
        (e.error ? [UIColor redColor] :
        (e.statusCode >= 400 ? [UIColor orangeColor] : [UIColor colorWithRed:0.10 green:0.72 blue:0.45 alpha:1.0])));
    cell.detailTextLabel.textColor = statusColor;
    // 副标题带请求开始时间（毫秒级），多请求排查时序时可直接对表
    cell.detailTextLabel.text = [NSString stringWithFormat:@"[%@] %@ · %@ · %lld B",
                                 [self.timeFormatter stringFromDate:e.startTime],
                                 [e statusText], [e durationText], (long long)e.responseSize];
    // 无障碍：整行朗读为「方法，URL，状态，耗时，大小，附加标记」摘要；点击看详情
    NSMutableString *netA11y = [NSMutableString string];
    [netA11y appendFormat:@"%@，", e.method];
    [netA11y appendString:e.url];
    [netA11y appendFormat:@"，%@，", [e statusText]];
    [netA11y appendFormat:@"耗时 %@，%lld 字节", [e durationText], (long long)e.responseSize];
    if (e.mocked) [netA11y appendString:@"，本地 Mock 响应"];
    else if (e.fromWeb) [netA11y appendString:@"，来自网页请求"];
    if (slow) [netA11y appendString:@"，慢请求"];
    if (e.error.length > 0) [netA11y appendFormat:@"，错误 %@", e.error];
    cell.isAccessibilityElement = YES;
    cell.accessibilityLabel = [netA11y copy];
    cell.accessibilityHint = @"轻点查看详情";

    // 搜索结果导航：当前匹配项加左侧橙色圆点 + 淡橙背景，与列表中其它命中（仅文本高亮）区分
    if (self.searchText.length > 0 && self.currentMatchRow >= 0 && indexPath.row == self.currentMatchRow) {
        UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 8)];
        dot.backgroundColor = VConsoleOrangeColor();
        dot.layer.cornerRadius = 4;
        cell.accessoryView = dot;
        cell.contentView.backgroundColor = [VConsoleOrangeColor() colorWithAlphaComponent:0.12];
    } else {
        cell.accessoryView = nil;
        cell.contentView.backgroundColor = [UIColor clearColor];
    }

    return cell;
}

/// 提供「展开全部 / 折叠」所需的最小行数：内容短到一屏就放得下时，
/// 折叠没有意义，也不应给一个无意义的按钮。
static const NSUInteger kVConsoleFoldMinLines = 40;

/// foldDepth = 0 表示完整展开；> 0 表示响应体按该深度折叠（用于详情默认折叠态）
- (NSString *)detailTextForEntry:(VConsoleNetworkEntry *)e foldDepth:(NSUInteger)foldDepth {
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"请求方法: %@\n", e.method];
    [s appendFormat:@"URL: %@\n", e.url];
    [s appendFormat:@"状态码: %@\n", [e statusText]];
    [s appendFormat:@"耗时: %@\n", [e durationText]];
    if (e.ttfbMs >= 0) {
        [s appendFormat:@"首字节(TTFB): %.0f ms\n", e.ttfbMs];
        // 时间轴条：TTFB 段 + 下载段，按比例绘制（共 24 格）
        double total = e.durationMs > 0 ? e.durationMs : (e.ttfbMs > 0 ? e.ttfbMs : 1);
        NSInteger ttfbCells = (NSInteger)round(24.0 * MAX(0, e.ttfbMs) / total);
        ttfbCells = MAX(0, MIN(24, ttfbCells));
        NSInteger dlCells = 24 - ttfbCells;
        NSString *bar = [NSString stringWithFormat:@"%@%@",
                         [@"█" stringByPaddingToLength:ttfbCells withString:@"█" startingAtIndex:0],
                         [@"░" stringByPaddingToLength:dlCells withString:@"░" startingAtIndex:0]];
        [s appendFormat:@"时间轴: [%@] TTFB %.0fms / 下载 %.0fms\n",
         bar, e.ttfbMs, MAX(0, e.durationMs - e.ttfbMs)];
    }
    [s appendFormat:@"响应大小: %lld B\n", (long long)e.responseSize];
    if (e.mocked) [s appendString:@"Mock: 是（本地数据，未发出真实请求）\n"];
    if (e.fromWeb) [s appendString:@"来源: WKWebView 页面 JS（fetch/XHR，经 JS 钩子回传）\n"];
    if (e.error) [s appendFormat:@"错误: %@\n", e.error];

    // 隐私脱敏：展示前涂抹请求/响应头与体中敏感字段（默认开启）
    BOOL redact = [VConsoleRedactor isEnabled];
    [s appendString:@"\n--- 请求头 ---\n"];
    for (NSString *k in e.requestHeaders) {
        NSString *v = e.requestHeaders[k];
        if (redact) v = [VConsoleRedactor redact:v];
        [s appendFormat:@"%@: %@\n", k, v];
    }
    if (e.requestBody.length) {
        NSString *body = redact ? [VConsoleRedactor redact:e.requestBody] : e.requestBody;
        [s appendFormat:@"\n--- 请求体 ---\n%@\n", body];
    }
    [s appendString:@"\n--- 响应头 ---\n"];
    for (NSString *k in e.responseHeaders) {
        NSString *v = e.responseHeaders[k];
        if (redact) v = [VConsoleRedactor redact:v];
        [s appendFormat:@"%@: %@\n", k, v];
    }
    if (e.responseBody.length) {
        [s appendString:@"\n--- 响应体 ---\n"];
        // 完整版与折叠版都走同一套递归实现（foldDepth=0 表示不折叠），
        // 保证两者「不相等」只可能是真的折叠掉了内容，而不是两套美化器的排版差异，
        // 否则极小 JSON 也会误显示「展开全部」按钮。
        NSString *body = [VConsoleJSONFormatter prettyBodyIfJSON:e.responseBody maxDepth:foldDepth];
        if (redact) body = [VConsoleRedactor redact:body];
        [s appendFormat:@"%@\n", body];
    }
    return s;
}

#pragma mark - cURL 导出（实现在 VConsoleNetworkEntry，此处仅引用）

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    VConsoleNetworkEntry *e = self.entries[indexPath.row];
    // 折叠版用于默认展示（一眼看清顶层结构），完整版供「展开全部」切换
    NSString *full = [self detailTextForEntry:e foldDepth:0];
    NSString *folded = [self detailTextForEntry:e foldDepth:[VConsoleJSONFormatter defaultFoldDepth]];
    // 内容短到一屏放得下时不提供折叠版，避免出现「点了只是几个空格差异」的无意义按钮
    if ([full componentsSeparatedByString:@"\n"].count < kVConsoleFoldMinLines) {
        folded = nil;
    }
    VConsoleDetailViewController *d = [[VConsoleDetailViewController alloc] initWithTitle:@"网络详情"
                                                                         detail:full
                                                                   foldedDetail:folded];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:d];
    [self presentViewController:nav animated:YES completion:nil];
}

/// 长按上下文菜单：复制 URL / 复制响应体 / 复制完整详情
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView
    contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
                                       point:(CGPoint)point {
    if (@available(iOS 13.0, *)) {
    if ((NSUInteger)indexPath.row >= self.entries.count) return nil;
    VConsoleNetworkEntry *e = self.entries[indexPath.row];
    __weak typeof(self) weakSelf = self;

    NSMutableArray<UIAction *> *actions = [NSMutableArray array];
    // 复制 cURL：终端复现请求的第一入口
    [actions addObject:[UIAction actionWithTitle:@"复制 cURL 命令"
                                            image:VConsoleImageNamed(@"terminal")
                                       identifier:nil
                                          handler:^(__kindof UIAction *action) {
        UIPasteboard.generalPasteboard.string = [e curlCommand];
        VConsoleHapticSuccess();
        [VConsoleToast showInView:weakSelf.view message:@"已复制 cURL 命令"];
    }]];
    [actions addObject:[UIAction actionWithTitle:@"复制 URL"
                                            image:VConsoleImageNamed(@"link")
                                       identifier:nil
                                          handler:^(__kindof UIAction *action) {
        UIPasteboard.generalPasteboard.string = e.url;
        VConsoleHapticSuccess();
        [VConsoleToast showInView:weakSelf.view message:@"已复制 URL"];
    }]];
    if (e.responseBody.length > 0) {
        [actions addObject:[UIAction actionWithTitle:@"复制响应体"
                                               image:VConsoleImageNamed(@"doc.on.doc")
                                          identifier:nil
                                             handler:^(__kindof UIAction *action) {
            UIPasteboard.generalPasteboard.string = e.responseBody;
            VConsoleHapticSuccess();
            [VConsoleToast showInView:weakSelf.view message:@"已复制响应体"];
        }]];
    }
    [actions addObject:[UIAction actionWithTitle:@"复制完整详情"
                                            image:VConsoleImageNamed(@"doc.on.doc.fill")
                                       identifier:nil
                                          handler:^(__kindof UIAction *action) {
        UIPasteboard.generalPasteboard.string = [weakSelf detailTextForEntry:e foldDepth:0];
        VConsoleHapticSuccess();
        [VConsoleToast showInView:weakSelf.view message:@"已复制完整详情"];
    }]];

    UIMenu *menu = [UIMenu menuWithTitle:e.method children:actions];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                      previewProvider:nil
                                                       actionProvider:^__kindof UIMenu *_Nullable(NSArray<__kindof UIAction *> *_Nullable suggestedActions) {
        return menu;
    }];
    }
    return nil;
}
#pragma clang diagnostic pop

@end
