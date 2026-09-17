#import "VConsoleCompat.h"
#import "VConsoleDetailViewController.h"
#import "VConsoleUICommon.h"
#import "VConsoleToast.h"

@interface VConsoleDetailViewController () <UISearchBarDelegate>
@property (nonatomic, copy) NSString *detailTitle;
@property (nonatomic, copy) NSString *detailText;
/// 折叠版文本（可为 nil）。非空且与 detailText 不同时才启用「展开全部 / 折叠」切换。
@property (nonatomic, copy, nullable) NSString *foldedText;
/// 是否已展开为完整内容
@property (nonatomic, assign) BOOL expanded;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong, nullable) UIBarButtonItem *toggleItem;
// 文本内查找
@property (nonatomic, strong) UIView *findBar;
@property (nonatomic, strong) UISearchBar *findSearchBar;
@property (nonatomic, strong) UILabel *findCountLabel;
@property (nonatomic, strong) NSLayoutConstraint *findBarHeightC;
@property (nonatomic, copy) NSArray<NSValue *> *matches;
@property (nonatomic, assign) NSInteger currentMatch;
/// 详情页进入时已播报过一次 VoiceOver 焦点（避免分享等子弹窗关闭后重复抢夺焦点）
@property (nonatomic, assign) BOOL voAnnounced;
/// 查找输入防抖块（可取消）
@property (nonatomic, strong, nullable) dispatch_block_t findDebounce;
@end

@implementation VConsoleDetailViewController

- (instancetype)initWithTitle:(NSString *)title detail:(NSString *)detail {
    return [self initWithTitle:title detail:detail foldedDetail:nil];
}

- (instancetype)initWithTitle:(NSString *)title
                       detail:(NSString *)detail
                 foldedDetail:(NSString *)foldedDetail {
    self = [super init];
    if (self) {
        _detailTitle = title ?: @"详情";
        _detailText = detail ?: @"";
        // 折叠版与完整版一致时（小 JSON / 非 JSON）没有切换的意义，直接置 nil
        _foldedText = (foldedDetail.length > 0 && ![foldedDetail isEqualToString:_detailText])
                      ? foldedDetail : nil;
        // 有折叠版时默认展示折叠态，让用户先看顶层结构
        _expanded = (_foldedText == nil);
        _currentMatch = -1;
    }
    return self;
}

/// 当前应展示的文本：展开态用完整版，否则用折叠版（无折叠版时即完整版）。
/// 查找 / 复制 / 分享都必须走这里，否则会与屏幕上看到的不一致。
- (NSString *)activeText {
    return self.expanded ? self.detailText : (self.foldedText ?: self.detailText);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = VConsoleBackgroundColor();
    self.title = self.detailTitle;

    // 查找条（默认隐藏，高度 0，不占布局空间）
    _findBar = [[UIView alloc] init];
    _findBar.backgroundColor = VConsoleTertiaryBackgroundColor();
    _findBar.translatesAutoresizingMaskIntoConstraints = NO;
    _findBar.clipsToBounds = YES;
    [self.view addSubview:_findBar];

    _findSearchBar = [[UISearchBar alloc] init];
    _findSearchBar.placeholder = @"在文本中查找";
    _findSearchBar.searchBarStyle = UISearchBarStyleMinimal;
    _findSearchBar.delegate = self;
    _findSearchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [_findBar addSubview:_findSearchBar];

    _findCountLabel = [[UILabel alloc] init];
    _findCountLabel.font = VConsoleFontForTextStyle(UIFontTextStyleCaption1);
    _findCountLabel.textColor = VConsoleSecondaryLabelColor();
    _findCountLabel.textAlignment = NSTextAlignmentCenter;
    _findCountLabel.text = @"0/0";
    _findCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_findBar addSubview:_findCountLabel];

    UIButton *prev = [UIButton buttonWithType:UIButtonTypeSystem];
    [prev setImage:VConsoleImageNamed(@"chevron.up") forState:UIControlStateNormal];
    [prev addTarget:self action:@selector(prevMatch) forControlEvents:UIControlEventTouchUpInside];
    // 无障碍：查找上一个/下一个匹配（图标按钮必须补 label）
    prev.isAccessibilityElement = YES;
    prev.accessibilityLabel = @"上一个匹配";
    prev.accessibilityHint = @"轻点跳到上一个查找结果";
    prev.accessibilityTraits = UIAccessibilityTraitButton;
    prev.translatesAutoresizingMaskIntoConstraints = NO;
    [_findBar addSubview:prev];

    UIButton *next = [UIButton buttonWithType:UIButtonTypeSystem];
    [next setImage:VConsoleImageNamed(@"chevron.down") forState:UIControlStateNormal];
    [next addTarget:self action:@selector(nextMatch) forControlEvents:UIControlEventTouchUpInside];
    // 无障碍：查找下一个匹配（图标按钮必须补 label）
    next.isAccessibilityElement = YES;
    next.accessibilityLabel = @"下一个匹配";
    next.accessibilityHint = @"轻点跳到下一个查找结果";
    next.accessibilityTraits = UIAccessibilityTraitButton;
    next.translatesAutoresizingMaskIntoConstraints = NO;
    [_findBar addSubview:next];

    // 正文（安全区约束，横竖屏 / 全面屏均可正确避开刘海与 home 条）
    // 长文本阅读是无障碍的核心场景，字号必须跟随系统设置
    _textView = [[UITextView alloc] init];
    _textView.editable = NO;
    _textView.font = VConsoleScaledMonospaceFont(12);
    _textView.text = [self activeText];
    _textView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_textView];

    _findBarHeightC = [_findBar.heightAnchor constraintEqualToConstant:0];
    _findBarHeightC.active = YES;
    if (@available(iOS 11.0, *)) {
        [_findBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor].active = YES;
    } else {
        [_findBar.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:20].active = YES;
    }
    [_findBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [_findBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;

    [_findSearchBar.leadingAnchor constraintEqualToAnchor:_findBar.leadingAnchor].active = YES;
    [_findSearchBar.centerYAnchor constraintEqualToAnchor:_findBar.centerYAnchor].active = YES;
    [_findCountLabel.leadingAnchor constraintEqualToAnchor:_findSearchBar.trailingAnchor constant:2].active = YES;
    [_findCountLabel.centerYAnchor constraintEqualToAnchor:_findBar.centerYAnchor].active = YES;
    [_findCountLabel.widthAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [prev.leadingAnchor constraintEqualToAnchor:_findCountLabel.trailingAnchor constant:2].active = YES;
    [prev.centerYAnchor constraintEqualToAnchor:_findBar.centerYAnchor].active = YES;
    [prev.widthAnchor constraintEqualToConstant:34].active = YES;
    [prev.heightAnchor constraintEqualToConstant:34].active = YES;
    [next.leadingAnchor constraintEqualToAnchor:prev.trailingAnchor constant:2].active = YES;
    // 关键修复：末端的 trailing 必须「等于」findBar 右边缘（原代码误用 <=，导致整条约束链
    // 右侧没有锚点、查找条整体可向左滑动，而 UISearchBar 不报告 intrinsic 宽度，最终被解算为
    // 宽度 0 —— 输入框塌缩、只剩放大镜图标。改为 = 后，next.trailing 被钉死，约束链在左右两端
    // 同时闭合：searchBar.leading(0) 与 next.trailing(findBar.trailing-6) 之间的所有宽度被逐一推算
    // 为定值（countLabel 取 max(固有宽度,44)，searchBar 吸收剩余空间），不再存在自由的未知量，
    // 既无歧义也不会与 countLabel 争抢空间。
    [next.trailingAnchor constraintEqualToAnchor:_findBar.trailingAnchor constant:-6].active = YES;
    [next.centerYAnchor constraintEqualToAnchor:_findBar.centerYAnchor].active = YES;
    [next.widthAnchor constraintEqualToConstant:34].active = YES;
    [next.heightAnchor constraintEqualToConstant:34].active = YES;

    [_textView.topAnchor constraintEqualToAnchor:_findBar.bottomAnchor].active = YES;
    [_textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8].active = YES;
    [_textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8].active = YES;
    if (@available(iOS 11.0, *)) {
        [_textView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-4].active = YES;
    } else {
        [_textView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-4].active = YES;
    }

    // 导航按钮：复制 / 分享 / 查找 / 完成
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithTitle:@"完成"
                                                             style:UIBarButtonItemStyleDone
                                                            target:self
                                                            action:@selector(done)];
    // 无障碍：右上角操作按钮都补 label + Button trait（图标按钮默认读不出名字）
    done.accessibilityLabel = @"完成";
    done.accessibilityTraits = UIAccessibilityTraitButton;
    UIBarButtonItem *share = [[UIBarButtonItem alloc] initWithImage:VConsoleImageNamed(@"square.and.arrow.up")
                                                              style:UIBarButtonItemStylePlain
                                                             target:self
                                                            action:@selector(shareText)];
    share.accessibilityLabel = @"分享内容";
    share.accessibilityHint = @"轻点分享当前文本";
    share.accessibilityTraits = UIAccessibilityTraitButton;
    UIBarButtonItem *find = [[UIBarButtonItem alloc] initWithImage:VConsoleImageNamed(@"magnifyingglass")
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(toggleFind)];
    find.accessibilityLabel = @"在文本中查找";
    find.accessibilityHint = @"轻点打开查找栏";
    find.accessibilityTraits = UIAccessibilityTraitButton;
    UIBarButtonItem *copy = [[UIBarButtonItem alloc] initWithImage:VConsoleImageNamed(@"doc.on.doc")
                                                              style:UIBarButtonItemStylePlain
                                                             target:self
                                                            action:@selector(copyText)];
    copy.accessibilityLabel = @"复制内容";
    copy.accessibilityHint = @"轻点复制当前文本";
    copy.accessibilityTraits = UIAccessibilityTraitButton;
    // 仅在存在折叠版时才插入「展开全部 / 折叠」，避免给日志/存储详情加无意义按钮
    NSMutableArray<UIBarButtonItem *> *rightItems = [NSMutableArray arrayWithObject:done];
    if (self.foldedText) {
        UIBarButtonItem *toggle = [[UIBarButtonItem alloc] initWithTitle:@"展开全部"
                                                                   style:UIBarButtonItemStylePlain
                                                                  target:self
                                                                  action:@selector(toggleExpanded)];
        self.toggleItem = toggle;
        toggle.accessibilityLabel = @"展开全部";
        toggle.accessibilityHint = @"轻点展开完整内容";
        toggle.accessibilityTraits = UIAccessibilityTraitButton;
        [rightItems addObject:toggle];
    }
    [rightItems addObject:share];
    [rightItems addObject:find];
    self.navigationItem.rightBarButtonItems = rightItems;
    self.navigationItem.leftBarButtonItem = copy;

    // 系统字号变化后正文要重设字体：查找高亮是把字号烘焙进 attributed string 的，
    // 正在查找时还要重新匹配一次，否则高亮范围会与新字号对不上
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onContentSizeChanged:)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];
}

#pragma mark - 无障碍

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // 进入详情页时把 VoiceOver 焦点移到正文（仅首次；分享/查找等子弹窗关闭后不再抢夺焦点）
    if (!self.voAnnounced) {
        self.voAnnounced = YES;
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, self.textView);
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)onContentSizeChanged:(NSNotification *)note {
    self.textView.font = VConsoleScaledMonospaceFont(12);
    self.findCountLabel.font = VConsoleFontForTextStyle(UIFontTextStyleCaption1);
    if (self.findSearchBar.text.length > 0) {
        [self findMatches];
    }
}

/// 在「折叠概览」与「完整内容」之间切换。切换后重跑查找，保证高亮与当前文本匹配。
- (void)toggleExpanded {
    if (!self.foldedText) return;
    self.expanded = !self.expanded;
    self.toggleItem.title = self.expanded ? @"折叠" : @"展开全部";
    self.toggleItem.accessibilityLabel = self.expanded ? @"折叠" : @"展开全部";
    self.textView.text = [self activeText];
    // 切换后旧的匹配区间已失效，清空高亮；若查找条开着则按新文本重新匹配
    self.findSearchBar.text = @"";
    self.matches = @[];
    self.currentMatch = -1;
    [self updateFindCount];
    [self rebuildHighlight];
    [self.textView setContentOffset:CGPointZero animated:NO];
    VConsoleHapticLight();
}

- (void)done {
    if (self.navigationController) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)copyText {
    [UIPasteboard generalPasteboard].string = [self activeText];
    VConsoleHapticSuccess();
    [VConsoleToast showInView:self.view message:(self.expanded ? @"已复制全部内容" : @"已复制当前内容")];
}

- (void)shareText {
    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[[self activeText]]
                                                                        applicationActivities:nil];
    avc.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
    [self presentViewController:avc animated:YES completion:nil];
}

#pragma mark - 文本内查找

- (void)toggleFind {
    BOOL willShow = (self.findBarHeightC.constant == 0);
    if (!willShow) {
        // 收起时清除高亮
        self.findSearchBar.text = @"";
        [self findMatches];
        [self.view endEditing:YES];
    }
    self.findBarHeightC.constant = willShow ? 44 : 0;
    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        [self.view layoutIfNeeded];
    } completion:^(BOOL finished) {
        if (willShow) [self.findSearchBar becomeFirstResponder];
    }];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    // 输入防抖：50k 字符长文本每次全量扫描+重建高亮开销大，停止输入 0.2s 后再执行
    if (self.findDebounce) {
        dispatch_block_cancel(self.findDebounce);
    }
    self.findDebounce = dispatch_block_create(0, ^{
        [self findMatches];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), self.findDebounce);
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    // 回车跳到下一个匹配
    [self nextMatch];
}

- (void)findMatches {
    NSMutableArray *out = [NSMutableArray array];
    NSString *query = self.findSearchBar.text;
    if (query.length > 0) {
        NSString *text = [self activeText];
        NSUInteger start = 0;
        while (start <= text.length) {
            NSRange searchRange = NSMakeRange(start, text.length - start);
            NSRange found = [text rangeOfString:query options:NSCaseInsensitiveSearch range:searchRange];
            if (found.location == NSNotFound) break;
            [out addObject:[NSValue valueWithRange:found]];
            start = found.location + MAX(found.length, 1);
        }
    }
    self.matches = out;
    self.currentMatch = (out.count > 0) ? 0 : -1;
    [self updateFindCount];
    [self rebuildHighlight];
    if (self.currentMatch >= 0) [self jumpToCurrent];
}

- (void)updateFindCount {
    self.findCountLabel.text = [NSString stringWithFormat:@"%ld/%lu",
                                (long)(self.currentMatch + 1), (unsigned long)self.matches.count];
}

/// 高亮所有匹配（黄色），当前项（橙色加深）
- (void)rebuildHighlight {
    UIFont *font = VConsoleScaledMonospaceFont(12);
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:[self activeText]
                                                                             attributes:@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: VConsoleLabelColor(),
    }];
    UIColor *normal = [VConsoleYellowColor() colorWithAlphaComponent:0.45];
    for (NSValue *v in self.matches) {
        [as addAttribute:NSBackgroundColorAttributeName value:normal range:v.rangeValue];
    }
    if (self.matches.count > 0 && self.currentMatch >= 0 && self.currentMatch < (NSInteger)self.matches.count) {
        NSRange cur = [self.matches[self.currentMatch] rangeValue];
        [as addAttribute:NSBackgroundColorAttributeName value:[VConsoleOrangeColor() colorWithAlphaComponent:0.85] range:cur];
        [as addAttribute:NSForegroundColorAttributeName value:[UIColor blackColor] range:cur];
    }
    self.textView.attributedText = as;
}

- (void)jumpToCurrent {
    if (self.currentMatch < 0 || self.currentMatch >= (NSInteger)self.matches.count) return;
    NSRange r = [self.matches[self.currentMatch] rangeValue];
    [self.textView scrollRangeToVisible:r];
    self.textView.selectedRange = r;
}

- (void)prevMatch {
    [self moveCurrentBy:-1];
}

- (void)nextMatch {
    [self moveCurrentBy:1];
}

/// 上一个/下一个：只重涂新旧两个匹配区间的样式（textStorage 原地编辑），
/// 避免 50k 字符全量重建 attributed string 造成的卡顿
- (void)moveCurrentBy:(NSInteger)delta {
    NSUInteger count = self.matches.count;
    if (count == 0) return;
    VConsoleHapticLight();
    NSInteger oldIdx = self.currentMatch;
    self.currentMatch = (self.currentMatch + delta + (NSInteger)count) % (NSInteger)count;
    [self updateFindCount];

    NSTextStorage *ts = self.textView.textStorage;
    UIColor *normal = [VConsoleYellowColor() colorWithAlphaComponent:0.45];
    [ts beginEditing];
    if (oldIdx >= 0 && oldIdx < (NSInteger)self.matches.count) {
        NSRange r = [self.matches[oldIdx] rangeValue];
        [ts addAttribute:NSBackgroundColorAttributeName value:normal range:r];
        [ts addAttribute:NSForegroundColorAttributeName value:VConsoleLabelColor() range:r];
    }
    if (self.currentMatch >= 0 && self.currentMatch < (NSInteger)self.matches.count) {
        NSRange r = [self.matches[self.currentMatch] rangeValue];
        [ts addAttribute:NSBackgroundColorAttributeName
                                      value:[VConsoleOrangeColor() colorWithAlphaComponent:0.85] range:r];
        [ts addAttribute:NSForegroundColorAttributeName value:[UIColor blackColor] range:r];
    }
    [ts endEditing];

    [self jumpToCurrent];
}

@end
