#import "VConsoleCompat.h"
#import "VConsoleSystemViewController.h"
#import "VConsoleUICommon.h"
#import "VConsoleSystemInfo.h"
#import "VConsoleDetailViewController.h"

@interface VConsoleSystemViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *items;
@end

@implementation VConsoleSystemViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = VConsoleBackgroundColor();
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [self.view addSubview:_tableView];
    [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = YES;
    [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;
    [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;

    // 下拉刷新：重新读取系统信息（电量 / 内存等会随时间变化）
    _tableView.refreshControl = [[UIRefreshControl alloc] init];
    [_tableView.refreshControl addTarget:self action:@selector(refreshTriggered)
                         forControlEvents:UIControlEventValueChanged];
    [self refresh];

    // 系统字号变化：行高是 automaticDimension，必须 reloadData 才会按新字号重算
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onContentSizeChanged:)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];
}

- (void)onContentSizeChanged:(NSNotification *)note {
    [_tableView reloadData];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)refresh {
    self.items = [VConsoleSystemInfo systemInfoItems];
    [_tableView reloadData];
}

- (void)refreshTriggered {
    [self refresh];
    [self.tableView.refreshControl endRefreshing];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"syscell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cid];
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.textColor = VConsoleLabelColor();
    }
    // 跟随动态字体（UIContentSizeCategoryDidChangeNotification 触发 reloadData 时，
    // 复用池中的 cell 需要重新套用缩放后的字号）
    cell.textLabel.font = VConsoleScaledFont(13, UIFontWeightRegular);
    cell.detailTextLabel.font = VConsoleScaledFont(12, UIFontWeightRegular);
    NSDictionary *d = self.items[indexPath.row];
    cell.textLabel.text = d[@"title"];
    cell.detailTextLabel.text = d[@"value"];
    // 无障碍：整行朗读为「标题，值」一句人话；值里多行/JSON 压成逗号连接，不念原始换行噪声
    NSString *sysTitle = d[@"title"] ?: @"";
    NSString *sysRaw = d[@"value"] ?: @"";
    NSString *sysFlat = [[sysRaw componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]
                         componentsJoinedByString:@"，"];
    if (sysFlat.length > 120) sysFlat = [[sysFlat substringToIndex:120] stringByAppendingString:@"…"];
    cell.isAccessibilityElement = YES;
    cell.accessibilityLabel = [NSString stringWithFormat:@"%@，%@", sysTitle, sysFlat];
    cell.accessibilityHint = @"轻点查看详情";
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *d = self.items[indexPath.row];
    VConsoleDetailViewController *vc = [[VConsoleDetailViewController alloc] initWithTitle:d[@"title"]
                                                                         detail:d[@"value"]];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [self presentViewController:nav animated:YES completion:nil];
}

@end
