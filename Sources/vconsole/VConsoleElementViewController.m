#import "VConsoleCompat.h"
#import "VConsoleElementViewController.h"
#import "VConsoleUICommon.h"

/// 视图树单节点（一次构建，扁平化时只决定显隐）。
@interface VConsoleViewNode : NSObject
@property (nonatomic, copy) NSString *className;
@property (nonatomic, assign) CGRect frame;
@property (nonatomic, assign) NSInteger depth;
@property (nonatomic, copy) NSString *address;
@property (nonatomic, assign) BOOL hidden;
@property (nonatomic, assign) CGFloat alpha;
@property (nonatomic, assign) NSInteger tag;
@property (nonatomic, assign) BOOL userInteractionEnabled;
@property (nonatomic, copy) NSString *backgroundColorDesc;
@property (nonatomic, assign) NSInteger childrenCount;
@property (nonatomic, strong) NSArray<VConsoleViewNode *> *children;
@end
@implementation VConsoleViewNode
@end

/// 防极端层级把面板拖垮：限制遍历深度与节点总数（UIKit 默认层级约 10~20 层，足矣）。
static const NSInteger kVConsoleElementMaxDepth = 40;
static const NSInteger kVConsoleElementMaxNodes = 4000;

@interface VConsoleElementViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) VConsoleEmptyStateView *emptyView;
@property (nonatomic, strong) NSArray<VConsoleViewNode *> *roots;       // 每个 UIWindow 一个根
@property (nonatomic, strong) NSMutableSet<NSString *> *expanded;        // 已展开节点的 address
@property (nonatomic, strong) NSMutableArray<VConsoleViewNode *> *flat;  // 展开后可见的扁平列表
@property (nonatomic, assign) NSInteger nodeBudget;
@end

@implementation VConsoleElementViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = VConsoleBackgroundColor();
    _expanded = [NSMutableSet set];
    _flat = [NSMutableArray array];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.estimatedRowHeight = 40;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    [self.view addSubview:_tableView];
    [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = YES;
    [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;
    [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;

    _tableView.refreshControl = [[UIRefreshControl alloc] init];
    [_tableView.refreshControl addTarget:self action:@selector(refreshTriggered)
                        forControlEvents:UIControlEventValueChanged];

    _emptyView = [[VConsoleEmptyStateView alloc] initWithSymbol:@"uiwindow"
                                                          title:@"暂无视图"
                                                       subtitle:@"当前没有可检视的窗口层级"];
    _emptyView.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyView.userInteractionEnabled = NO;
    [self.view addSubview:_emptyView];
    [_emptyView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
    [_emptyView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor].active = YES;

    [self refresh];
}

- (void)refreshTriggered {
    [self refresh];
    [self.tableView.refreshControl endRefreshing];
}

- (void)refresh {
    self.nodeBudget = kVConsoleElementMaxNodes;
    NSMutableArray *roots = [NSMutableArray array];
    // 仅遍历常规层级（windowLevel == Normal）的窗口，跳过 vConsole 自身的浮层窗口
    // （悬浮球窗口、面板窗口层级更高，且非业务视图，纳入只会干扰调试）。
    for (UIWindow *win in [UIApplication sharedApplication].windows) {
        if (win.windowLevel != UIWindowLevelNormal) continue;
        VConsoleViewNode *root = [self nodeForView:win depth:0];
        root.className = [NSString stringWithFormat:@"%@ (window)", NSStringFromClass(win.class)];
        [roots addObject:root];
        if (self.nodeBudget <= 0) break;
    }
    self.roots = roots;
    [self flatten];
    [self.tableView reloadData];
    self.emptyView.hidden = (roots.count > 0);
}

/// 由 UIView 构建节点（递归受深度与预算限制）。
- (VConsoleViewNode *)nodeForView:(UIView *)view depth:(NSInteger)depth {
    VConsoleViewNode *n = [[VConsoleViewNode alloc] init];
    n.className = NSStringFromClass(view.class);
    n.frame = view.frame;
    n.depth = depth;
    n.address = [NSString stringWithFormat:@"%p", view];
    n.hidden = view.hidden;
    n.alpha = view.alpha;
    n.tag = view.tag;
    n.userInteractionEnabled = view.userInteractionEnabled;
    n.backgroundColorDesc = [self colorDesc:view.backgroundColor];
    if (depth < kVConsoleElementMaxDepth && self.nodeBudget > 0) {
        NSMutableArray *kids = [NSMutableArray array];
        for (UIView *sv in view.subviews) {
            [kids addObject:[self nodeForView:sv depth:depth + 1]];
            self.nodeBudget--;
            if (self.nodeBudget <= 0) break;
        }
        n.children = kids;
    } else {
        n.children = @[];
    }
    n.childrenCount = n.children.count;
    return n;
}

- (void)flatten {
    [self.flat removeAllObjects];
    for (VConsoleViewNode *root in self.roots) [self flattenNode:root];
}

- (void)flattenNode:(VConsoleViewNode *)n {
    [self.flat addObject:n];
    if (n.children.count > 0 && [self.expanded containsObject:n.address]) {
        for (VConsoleViewNode *c in n.children) [self flattenNode:c];
    }
}

- (NSString *)colorDesc:(UIColor *)color {
    if (!color) return @"nil";
    CGFloat r, g, b, a;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"rgba(%.0f,%.0f,%.0f,%.2f)", r * 255, g * 255, b * 255, a];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.flat.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"vcs.element.cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
        cell.textLabel.font = VConsoleScaledFont(13, UIFontWeightRegular);
        cell.detailTextLabel.font = VConsoleScaledFont(11, UIFontWeightRegular);
        cell.detailTextLabel.textColor = VConsoleSecondaryLabelColor();
        cell.textLabel.textColor = VConsoleLabelColor();
        cell.indentationWidth = 14;
        // 无障碍：视图树逐行朗读，cell 默认即可被 VoiceOver 识别
        cell.isAccessibilityElement = YES;
    }
    VConsoleViewNode *n = self.flat[indexPath.row];
    cell.textLabel.text = n.className;
    NSMutableString *sub = [NSMutableString stringWithFormat:@"%@  α%.2f",
                            NSStringFromCGRect(n.frame), n.alpha];
    if (n.hidden) [sub appendString:@"  hidden"];
    if (n.tag != 0) [sub appendFormat:@"  tag=%ld", (long)n.tag];
    if (n.childrenCount > 0) [sub appendFormat:@"  ·%ld subviews", (long)n.childrenCount];
    cell.detailTextLabel.text = sub;
    cell.indentationLevel = n.depth;
    if (n.childrenCount > 0) {
        cell.accessoryType = [self.expanded containsObject:n.address]
            ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    VConsoleViewNode *n = self.flat[indexPath.row];
    if (n.childrenCount == 0) return;
    if ([self.expanded containsObject:n.address]) [self.expanded removeObject:n.address];
    else [self.expanded addObject:n.address];
    [self flatten];
    [tableView reloadData];
}

@end
