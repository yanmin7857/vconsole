#import "VConsoleCompat.h"
#import "VConsoleLogViewController.h"
#import "VConsoleLogger.h"
#import "VConsoleLogEntry.h"
#import "VConsoleDetailViewController.h"
#import "VConsoleJSONFormatter.h"
#import "VConsoleUICommon.h"
#import "VConsoleToast.h"

static UIColor *vconsoleColorForLevel(VConsoleLogLevel level) {
    switch (level) {
        case VConsoleLogLevelVerbose: return [UIColor blackColor];
        case VConsoleLogLevelDebug:   return [UIColor colorWithRed:0.20 green:0.55 blue:0.90 alpha:1.0];
        case VConsoleLogLevelInfo:    return VConsoleGrayColor();
        case VConsoleLogLevelWarn:    return [UIColor colorWithRed:0.95 green:0.65 blue:0.15 alpha:1.0];
        case VConsoleLogLevelError:   return [UIColor colorWithRed:0.90 green:0.25 blue:0.25 alpha:1.0];
    }
    return [UIColor blackColor];
}

/// 刷新合并窗口（秒）：高频日志（压测）时窗口内的多次变更只触发一次刷新，
/// 避免每条日志都 reloadData 导致主线程卡顿。
static const NSTimeInterval kVConsoleRefreshCoalesceInterval = 0.25;
/// 搜索输入防抖（秒）
static const NSTimeInterval kVConsoleSearchDebounceInterval = 0.15;

@interface VConsoleLogViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIScrollView *chipsScroll;
@property (nonatomic, strong) UIStackView *chipStack;
@property (nonatomic, strong) NSArray<UIButton *> *chipButtons;
@property (nonatomic, strong) UIButton *clearButton;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) VConsoleEmptyStateView *emptyView;
/// 回到底部浮动按钮（滚离底部时出现）
@property (nonatomic, strong) UIButton *scrollBottomButton;
@property (nonatomic, strong) NSArray<VConsoleLogEntry *> *entries;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic, assign) NSInteger chipLevel;   // -1 = 全部
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

@implementation VConsoleLogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = VConsoleBackgroundColor();

    // NSDateFormatter 创建昂贵，全局只建一次复用
    _timeFormatter = [[NSDateFormatter alloc] init];
    _timeFormatter.dateFormat = @"HH:mm:ss";
    _chipLevel = -1;

    // 搜索栏
    _searchBar = [[UISearchBar alloc] init];
    _searchBar.placeholder = @"搜索日志内容";
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.delegate = self;
    _searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_searchBar];

    // 级别筛选 chips（水平滚动）
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
        [_chipStack.leadingAnchor constraintEqualToAnchor:_chipsScroll.leadingAnchor constant:12].active = YES;
        [_chipStack.trailingAnchor constraintLessThanOrEqualToAnchor:_chipsScroll.trailingAnchor constant:-12].active = YES;
        [_chipStack.centerYAnchor constraintEqualToAnchor:_chipsScroll.centerYAnchor].active = YES;
    }

    // 列表
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    // 开启自动行高并给出估算值：日志行高差异极大（单行文本 vs 8 行 JSON 摘要），
    // 不给出估算值时系统在滚动中反复修正 contentSize，会造成明显跳动。
    _tableView.estimatedRowHeight = 44;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    [self.view addSubview:_tableView];

    // 底部操作栏
    UIView *bar = [[UIView alloc] init];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = VConsoleTertiaryBackgroundColor();
    [self.view addSubview:bar];

    _countLabel = [[UILabel alloc] init];
    // 刻意不跟随动态字体：这是底部 40pt 操作栏里的文字，横向空间固定，
    // 跟随会与右侧「清空日志」按钮撞在一起。参见 VConsoleUICommon.h 的例外清单。
    _countLabel.font = [UIFont systemFontOfSize:12];
    _countLabel.textColor = VConsoleSecondaryLabelColor();
    _countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:_countLabel];

    _clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_clearButton setTitle:@"清空日志" forState:UIControlStateNormal];
    _clearButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_clearButton addTarget:self action:@selector(clear) forControlEvents:UIControlEventTouchUpInside];
    // 无障碍：清空按钮（文字按钮也显式声明，确保 label/hint/trait 一致可控）
    _clearButton.isAccessibilityElement = YES;
    _clearButton.accessibilityLabel = @"清空日志";
    _clearButton.accessibilityHint = @"删除全部日志，操作不可撤销";
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
    _emptyView = [[VConsoleEmptyStateView alloc] initWithSymbol:@"doc.text.magnifyingglass"
                                                      title:@"暂无日志"
                                                   subtitle:@"使用 VConsoleLog* 宏或 NSLog 输出"];
    _emptyView.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyView.hidden = YES;
    [self.view addSubview:_emptyView];

    // 回到底部浮动按钮：滚离底部时出现
    _scrollBottomButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_scrollBottomButton setImage:VConsoleImageNamed(@"arrow.down.to.line.circle.fill")
                         forState:UIControlStateNormal];
    _scrollBottomButton.tintColor = [UIColor colorWithRed:0.10 green:0.72 blue:0.45 alpha:1.0];
    _scrollBottomButton.backgroundColor = VConsoleSecondaryBackgroundColor();
    _scrollBottomButton.layer.cornerRadius = 20;
    _scrollBottomButton.layer.shadowColor = [UIColor blackColor].CGColor;
    _scrollBottomButton.layer.shadowOpacity = 0.15;
    _scrollBottomButton.layer.shadowOffset = CGSizeMake(0, 2);
    _scrollBottomButton.layer.shadowRadius = 4;
    _scrollBottomButton.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollBottomButton.hidden = YES;
    [_scrollBottomButton addTarget:self action:@selector(scrollToBottomTapped)
                  forControlEvents:UIControlEventTouchUpInside];
    // 无障碍：回到底部浮动按钮无文字，必须补 label，否则 VoiceOver 读不出
    _scrollBottomButton.isAccessibilityElement = YES;
    _scrollBottomButton.accessibilityLabel = @"回到底部";
    _scrollBottomButton.accessibilityHint = @"轻点滚动到最新日志";
    _scrollBottomButton.accessibilityTraits = UIAccessibilityTraitButton;
    [self.view addSubview:_scrollBottomButton];

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
    [_clearButton.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-12].active = YES;
    [_clearButton.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor].active = YES;
    [_emptyView.centerXAnchor constraintEqualToAnchor:_tableView.centerXAnchor].active = YES;
    [_emptyView.centerYAnchor constraintEqualToAnchor:_tableView.centerYAnchor].active = YES;
    [_scrollBottomButton.trailingAnchor constraintEqualToAnchor:_tableView.trailingAnchor constant:-16].active = YES;
    [_scrollBottomButton.bottomAnchor constraintEqualToAnchor:_tableView.bottomAnchor constant:-12].active = YES;
    [_scrollBottomButton.widthAnchor constraintEqualToConstant:40].active = YES;
    [_scrollBottomButton.heightAnchor constraintEqualToConstant:40].active = YES;

    // 搜索结果导航：底部操作栏右侧（清空按钮左侧）的 ‹ k/N ›
    [_matchCountLabel.trailingAnchor constraintEqualToAnchor:_clearButton.leadingAnchor constant:-8].active = YES;
    [_matchCountLabel.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor].active = YES;
    [_matchCountLabel.widthAnchor constraintGreaterThanOrEqualToConstant:42].active = YES;
    [_matchNextButton.trailingAnchor constraintEqualToAnchor:_matchCountLabel.leadingAnchor constant:-2].active = YES;
    [_matchNextButton.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor].active = YES;
    [_matchPrevButton.trailingAnchor constraintEqualToAnchor:_matchNextButton.leadingAnchor constant:-2].active = YES;
    [_matchPrevButton.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor].active = YES;

    [self buildChips];

    // 通知已由 VConsoleLogger 派发到主线程，这里直接处理（含节流合并）
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onLogChanged)
                                                 name:VConsoleLoggerDidAddEntryNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onLogChanged)
                                                 name:VConsoleLoggerDidClearNotification
                                               object:nil];
    // 系统字号变化：行高是 automaticDimension，必须 reloadData 才会按新字号重算
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onContentSizeChanged:)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];
    [self refresh];
}

- (void)onContentSizeChanged:(NSNotification *)note {
    [_tableView reloadData];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - 筛选

- (void)buildChips {
    NSArray<NSString *> *titles = @[@"全部", @"Verbose", @"Debug", @"Info", @"Warn", @"Error"];
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.tag = i - 1; // -1 = 全部，其余对应 VConsoleLogLevel
        // 刻意不跟随动态字体：chip 是固定 26pt 高的圆角胶囊，字号变大会撑破圆角背景。
        // 参见 VConsoleUICommon.h 里「动态字体的例外清单」。
        b.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        b.layer.cornerRadius = 13;
        b.layer.masksToBounds = YES;
        // contentEdgeInsets 在 iOS 15 起被标记 deprecated（仅在配置 UIButtonConfiguration 时被忽略），
        // 此处未使用 configuration，行为不变；用 pragma 保持零警告构建
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        b.contentEdgeInsets = UIEdgeInsetsMake(5, 12, 5, 12);
#pragma clang diagnostic pop
        [b setTitle:titles[i] forState:UIControlStateNormal];
        [b addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
        b.translatesAutoresizingMaskIntoConstraints = NO;
        // 无障碍：筛选标签，显式声明可聚焦并给出提示
        b.isAccessibilityElement = YES;
        b.accessibilityHint = @"轻点按该级别筛选日志";
        [b.heightAnchor constraintEqualToConstant:26].active = YES;
        [_chipStack addArrangedSubview:b];
        [buttons addObject:b];
    }
    _chipButtons = [buttons copy];
    [self updateChipAppearance];
}

- (void)chipTapped:(UIButton *)sender {
    if (self.chipLevel == sender.tag) return;
    self.chipLevel = sender.tag;
    VConsoleHapticLight();
    [self updateChipAppearance];
    [self refresh];
}

- (void)updateChipAppearance {
    for (UIButton *b in self.chipButtons) {
        BOOL selected = (b.tag == self.chipLevel);
        UIColor *color = (b.tag < 0) ? [UIColor colorWithRed:0.10 green:0.72 blue:0.45 alpha:1.0]
                                     : vconsoleColorForLevel((VConsoleLogLevel)b.tag);
        if (selected) {
            b.backgroundColor = color;
            [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        } else {
            b.backgroundColor = VConsoleSecondarySystemFillColor();
            [b setTitleColor:VConsoleLabelColor() forState:UIControlStateNormal];
        }
        // 无障碍：选中的筛选标签加 Selected trait，VoiceOver 用户才知道当前生效的级别
        b.accessibilityTraits = selected ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected)
                                         : UIAccessibilityTraitButton;
    }
}

- (BOOL)isFiltered {
    return (self.chipLevel >= 0 || self.searchText.length > 0);
}

- (NSArray<VConsoleLogEntry *> *)filteredFrom:(NSArray<VConsoleLogEntry *> *)all {
    if (![self isFiltered]) return all;
    NSString *q = self.searchText;
    NSInteger lvl = self.chipLevel;
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:all.count];
    for (VConsoleLogEntry *e in all) {
        if (lvl >= 0 && e.level != lvl) continue;
        if (q.length > 0 &&
            [e.message rangeOfString:q options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
        [out addObject:e];
    }
    return out;
}

#pragma mark - 刷新

- (void)onLogChanged {
    if (self.refreshPending) return;
    self.refreshPending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kVConsoleRefreshCoalesceInterval * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.refreshPending = NO;
        [self refresh];
    });
}

- (void)refresh {
    NSArray *all = [[VConsoleLogger shared] allEntries];
    BOOL filtered = [self isFiltered];
    NSArray *shown = [self filteredFrom:all];
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

    // 过滤态下行号与全量数组不对应，直接全量刷新；未过滤时增量插入
    if (!filtered && newCount > oldCount && oldCount > 0 && (newCount - oldCount) <= 200) {
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

    [self updateEmptyState:all.count];

    // 用户原本就在底部看最新日志时，自动跟随滚动
    if (wasAtBottom && newCount > 0) {
        [_tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:newCount - 1 inSection:0]
                          atScrollPosition:UITableViewScrollPositionBottom
                                  animated:NO];
    }

    [self updateMatchNavigation];
}

- (void)updateEmptyState:(NSUInteger)totalCount {
    if (self.entries.count > 0) {
        self.emptyView.hidden = YES;
        return;
    }
    if ([self isFiltered]) {
        [self.emptyView configureSymbol:@"magnifyingglass"
                                  title:@"无匹配结果"
                               subtitle:@"换个关键词，或点击「全部」清除筛选"];
    } else {
        [self.emptyView configureSymbol:@"doc.text.magnifyingglass"
                                  title:@"暂无日志"
                               subtitle:@"使用 VConsoleLog* 宏或 NSLog 输出"];
    }
    self.emptyView.hidden = NO;
}

- (BOOL)isTableViewAtBottom {
    CGFloat offset = _tableView.contentOffset.y;
    CGFloat contentH = _tableView.contentSize.height;
    CGFloat frameH = _tableView.frame.size.height;
    if (contentH <= frameH) return YES;
    return (contentH - offset - frameH) < 60;
}

#pragma mark - 回到底部

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    BOOL show = (self.entries.count > 0) && (![self isTableViewAtBottom]);
    if (self.scrollBottomButton.hidden == show) {
        self.scrollBottomButton.hidden = !show;
    }
}

- (void)scrollToBottomTapped {
    if (self.entries.count == 0) return;
    VConsoleHapticLight();
    [_tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:self.entries.count - 1 inSection:0]
                      atScrollPosition:UITableViewScrollPositionBottom
                              animated:YES];
}

- (void)clear {
    // 条数取未过滤的全量：清空是删库操作，提示里必须是真实要删除的量，
    // 而不是当前筛选后看到的条数。VConsoleLogger 对外只有 allEntries（无 entries）。
    NSUInteger total = [[VConsoleLogger shared] allEntries].count;
    if (total == 0) {
        [VConsoleToast showInView:self.view message:@"暂无日志可清空"];
        return;
    }
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"清空日志？"
                                                                message:[NSString stringWithFormat:@"将删除 %lu 条日志，此操作不可撤销。", (unsigned long)total]
                                                         preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"清空"
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *action) {
        // 触觉放在确认之后：没确认就先震一下是错误的反馈
        VConsoleHapticWarning();
        [[VConsoleLogger shared] clear];
        [VConsoleToast showInView:weakSelf.view message:@"已清空日志"];
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
    static NSString *cid = @"logcell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
        cell.detailTextLabel.textColor = VConsoleSecondaryLabelColor();
    }
    VConsoleLogEntry *e = self.entries[indexPath.row];
    UIColor *levelColor = vconsoleColorForLevel(e.level);
    // 有搜索词时给命中片段加背景高亮，让用户一眼看出这条为什么被匹配出来。
    // 无搜索词必须先把 attributedText 置 nil 再赋 text，否则复用 cell 会残留上一次的高亮。
    NSString *q = (self.searchText.length > 0) ? self.searchText : nil;
    NSString *text = nil;
    UIFont *font = nil;
    if (e.messageLooksLikeJSON) {
        // 列表用截断摘要（前 8 行），避免单条巨型 JSON 把日志流撑爆
        text = e.summaryMessage;
        font = VConsoleScaledMonospaceFont(12);
    } else {
        text = e.message ?: @"";
        font = VConsoleScaledFont(13, UIFontWeightRegular);
    }
    cell.textLabel.font = font;
    cell.textLabel.textColor = levelColor;
    // 字体必须每次都设（不能只在 cell 创建时设）：系统字号变化后复用池里的旧 cell
    // 还带着旧字号，reloadData 也不会重走创建分支。
    cell.detailTextLabel.font = VConsoleScaledFont(11, UIFontWeightRegular);
    if (q) {
        // 高亮串自带前景色（= 级别色），不要再依赖 textLabel.textColor 兜底
        cell.textLabel.attributedText = VConsoleHighlightedText(text, q, font, levelColor);
    } else {
        cell.textLabel.attributedText = nil;
        cell.textLabel.text = text;
    }
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"[%@] %@ · %@:%ld",
                                 [self.timeFormatter stringFromDate:e.timestamp], e.levelName,
                                 e.file ?: @"", (long)e.line];
    // 无障碍：整行朗读为「级别，时间，文件:行号，内容」摘要；点击可看完整详情
    NSMutableString *logA11y = [NSMutableString string];
    [logA11y appendFormat:@"%@，", e.levelName];
    [logA11y appendFormat:@"%@，", [self.timeFormatter stringFromDate:e.timestamp]];
    if (e.file.length > 0) [logA11y appendFormat:@"%@:%ld，", e.file, (long)e.line];
    [logA11y appendString:text];
    cell.isAccessibilityElement = YES;
    cell.accessibilityLabel = [logA11y copy];
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

- (NSString *)detailTextForEntry:(VConsoleLogEntry *)e {
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"时间: %@\n", e.timestamp];
    [s appendFormat:@"级别: %@\n", e.levelName];
    if (e.file) [s appendFormat:@"文件: %@:%ld\n", e.file, (long)e.line];
    if (e.function) [s appendFormat:@"函数: %@\n", e.function];
    // 详情用完整的 displayMessage：列表截断了，详情不能跟着丢内容，
    // 否则又回到用户抱怨的「看不到具体的」。JSON 时这里是美化后的全文。
    [s appendFormat:@"\n%@\n", e.displayMessage];
    return s;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    VConsoleLogEntry *e = self.entries[indexPath.row];
    VConsoleDetailViewController *d = [[VConsoleDetailViewController alloc] initWithTitle:@"日志详情"
                                                                         detail:[self detailTextForEntry:e]];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:d];
    [self presentViewController:nav animated:YES completion:nil];
}

/// 长按上下文菜单：复制消息 / 复制完整详情
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView
    contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
                                       point:(CGPoint)point {
    if (@available(iOS 13.0, *)) {
    if ((NSUInteger)indexPath.row >= self.entries.count) return nil;
    VConsoleLogEntry *e = self.entries[indexPath.row];
    __weak typeof(self) weakSelf = self;

    UIAction *copyMsg = [UIAction actionWithTitle:@"复制消息"
                                            image:VConsoleImageNamed(@"doc.on.doc")
                                       identifier:nil
                                          handler:^(__kindof UIAction *action) {
        UIPasteboard.generalPasteboard.string = e.message;
        VConsoleHapticSuccess();
        [VConsoleToast showInView:weakSelf.view message:@"已复制消息"];
    }];
    UIAction *copyDetail = [UIAction actionWithTitle:@"复制完整详情"
                                               image:VConsoleImageNamed(@"doc.on.doc.fill")
                                          identifier:nil
                                             handler:^(__kindof UIAction *action) {
        UIPasteboard.generalPasteboard.string = [weakSelf detailTextForEntry:e];
        VConsoleHapticSuccess();
        [VConsoleToast showInView:weakSelf.view message:@"已复制完整详情"];
    }];
    UIMenu *menu = [UIMenu menuWithTitle:e.levelName children:@[copyMsg, copyDetail]];
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
