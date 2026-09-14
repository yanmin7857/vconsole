#import "VConsoleCompat.h"
#import "VConsoleStorageViewController.h"
#import "VConsoleStorageInspector.h"
#import "VConsoleDetailViewController.h"
#import "VConsoleUICommon.h"
#import "VConsoleToast.h"

/// 文本预览的大小上限：超过则提示过大，避免一次性读入大文件
static const long long kVConsoleMaxPreviewBytes = 256 * 1024;

/// 去掉首尾空白与换行（新增/编辑键名时避免误存带空格的键）
static NSString *VConsoleStorageTrimmed(NSString *s) {
    if (![s isKindOfClass:[NSString class]]) return @"";
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

/// 写 UserDefaults / 弹窗 / toast 都必须在主线程；菜单回调理论上已在主线程，这里做兜底。
static void VConsoleStorageRunOnMain(dispatch_block_t block) {
    if (!block) return;
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

@interface VConsoleStorageViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITextField *searchField;
/// 新增键值入口（放在搜索框右侧）
@property (nonatomic, strong) UIButton *addButton;
@property (nonatomic, strong) UITableView *tableView;
// 新增键值弹窗的临时引用：用于实时校验「键/值都非空」开关确认按钮、动态提示键是否已存在。
// 弹窗消失后立即置 nil，避免长期持有。
@property (nonatomic, strong, nullable) UIAlertController *addAlertController;
@property (nonatomic, strong, nullable) UITextField *addKeyField;
@property (nonatomic, strong, nullable) UITextField *addValueField;
@property (nonatomic, strong, nullable) UIAlertAction *addConfirmAction;
@property (nonatomic, strong) NSArray<NSDictionary *> *allDefaultsItems;
@property (nonatomic, strong) NSArray<NSDictionary *> *allFileItems;
@property (nonatomic, strong) NSArray<NSDictionary *> *defaultsItems; // 搜索过滤后
@property (nonatomic, strong) NSArray<NSDictionary *> *fileItems;     // 搜索过滤后
@property (nonatomic, strong) VConsoleEmptyStateView *emptyView;
/// 目录导航栈（路径）。空 = 根层（Documents/Library/tmp）；非空 = 栈顶为当前目录。
@property (nonatomic, strong) NSMutableArray<NSString *> *dirStack;
@end

@implementation VConsoleStorageViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = VConsoleBackgroundColor();
    _dirStack = [NSMutableArray array];

    if (@available(iOS 13.0, *)) {
        _searchField = [[UISearchTextField alloc] init];
    } else {
        _searchField = [[UITextField alloc] init];
    }
    _searchField.placeholder = @"搜索 UserDefaults 键 / 文件名";
    // 刻意不跟随动态字体：搜索框是固定 36pt 高的容器，字号变大会竖向裁切。
    // 参见 VConsoleUICommon.h 的例外清单。
    _searchField.font = [UIFont systemFontOfSize:14];
    _searchField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _searchField.translatesAutoresizingMaskIntoConstraints = NO;
    [_searchField addTarget:self action:@selector(searchChanged:) forControlEvents:UIControlEventEditingChanged];
    [self.view addSubview:_searchField];

    // 新增键值按钮：独立控件 + 约束布局（不用 searchField.rightView —— UISearchTextField
    // 自己管理 rightView 区域（clearButton/搜索图标），塞自定义 view 容易与系统视图打架）
    _addButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _addButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_addButton setImage:VConsoleImageNamed(@"plus.circle.fill") forState:UIControlStateNormal];
    _addButton.tintColor = VConsoleBlueColor();
    // 无障碍：图标按钮必须补 label + hint + Button trait，否则 VoiceOver 读不出
    _addButton.isAccessibilityElement = YES;
    _addButton.accessibilityLabel = @"新增 UserDefaults 键值";
    _addButton.accessibilityHint = @"轻点添加一个键值对";
    _addButton.accessibilityTraits = UIAccessibilityTraitButton;
    [_addButton addTarget:self action:@selector(addButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_addButton];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    // 自动行高：字号调大后固定 44 会截断文本
    _tableView.estimatedRowHeight = 44;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    [self.view addSubview:_tableView];

    [_searchField.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:8].active = YES;
    [_searchField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12].active = YES;
    [_searchField.heightAnchor constraintEqualToConstant:36].active = YES;
    // 搜索框让出右侧空间给「+」按钮
    [_searchField.trailingAnchor constraintEqualToAnchor:_addButton.leadingAnchor constant:-8].active = YES;
    [_addButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12].active = YES;
    [_addButton.centerYAnchor constraintEqualToAnchor:_searchField.centerYAnchor].active = YES;
    [_addButton.widthAnchor constraintEqualToConstant:32].active = YES;
    [_addButton.heightAnchor constraintEqualToConstant:32].active = YES;
    [_tableView.topAnchor constraintEqualToAnchor:_searchField.bottomAnchor constant:4].active = YES;
    [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;
    [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;

    // 下拉刷新：重新扫描沙盒与 UserDefaults
    _tableView.refreshControl = [[UIRefreshControl alloc] init];
    [_tableView.refreshControl addTarget:self action:@selector(refreshTriggered)
                         forControlEvents:UIControlEventValueChanged];

    // 空态（覆盖在列表区域中央，不拦截点击）
    _emptyView = [[VConsoleEmptyStateView alloc] initWithSymbol:@"externaldrive"
                                                      title:@"暂无数据"
                                                   subtitle:@""];
    _emptyView.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyView.hidden = YES;
    [self.view addSubview:_emptyView];
    [_emptyView.centerXAnchor constraintEqualToAnchor:_tableView.centerXAnchor].active = YES;
    [_emptyView.centerYAnchor constraintEqualToAnchor:_tableView.centerYAnchor].active = YES;

    // 系统字号变化：行高按新字号重算（cell 字体每次 cellForRow 重设，reloadData 即可）
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onContentSizeChanged:)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];

    [self refresh];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)onContentSizeChanged:(NSNotification *)note {
    [self.tableView reloadData];
}

- (void)searchChanged:(UITextField *)sender {
    [self applyFilter];
}

- (void)refresh {
    // 遍历沙盒目录、解析全部 UserDefaults 可能耗时，放后台执行
    BOOL inRoot = (self.dirStack.count == 0);
    NSString *currentDir = inRoot ? nil : self.dirStack.lastObject;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *defaults = [[VConsoleStorageInspector shared] userDefaultsItems];
        // 根层显示三个沙盒目录入口；进入目录后非递归列举其内容
        NSArray *files = inRoot ? [[VConsoleStorageInspector shared] sandboxRootItems]
                                : [[VConsoleStorageInspector shared] fileItemsInDirectory:currentDir];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.allDefaultsItems = defaults;
            self.allFileItems = files;
            [self.tableView.refreshControl endRefreshing];
            [self applyFilter];
        });
    });
}

- (void)refreshTriggered {
    [self refresh];
}

- (void)applyFilter {
    NSString *query = self.searchField.text;
    if (query.length == 0) {
        self.defaultsItems = self.allDefaultsItems;
        self.fileItems = self.allFileItems;
    } else {
        NSPredicate *p1 = [NSPredicate predicateWithFormat:@"key CONTAINS[c] %@", query];
        self.defaultsItems = [self.allDefaultsItems filteredArrayUsingPredicate:p1];
        NSPredicate *p2 = [NSPredicate predicateWithFormat:@"name CONTAINS[c] %@ OR path CONTAINS[c] %@", query, query];
        self.fileItems = [self.allFileItems filteredArrayUsingPredicate:p2];
    }
    [self.tableView reloadData];
    [self updateEmptyState];
}

- (void)updateEmptyState {
    // 两个 section 都为空才显示整体空态（避免覆盖 section 头）
    BOOL allEmpty = (self.defaultsItems.count == 0 && self.fileItems.count == 0);
    self.emptyView.hidden = !allEmpty;
    if (!allEmpty) return;
    if (self.searchField.text.length > 0) {
        [self.emptyView configureSymbol:@"magnifyingglass"
                                  title:@"无匹配结果"
                               subtitle:@"换个关键词试试"];
    } else {
        [self.emptyView configureSymbol:@"externaldrive"
                                  title:@"沙盒为空"
                               subtitle:@"下拉可重新扫描"];
    }
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"UserDefaults";
    if (self.dirStack.count == 0) return @"沙盒目录（点目录进入浏览）";
    return [NSString stringWithFormat:@"当前目录: %@",
            [self.dirStack.lastObject stringByReplacingOccurrencesOfString:NSHomeDirectory()
                                                                withString:@"~"]];
}

/// 文件 section 是否显示「返回上级」行
- (BOOL)hasParentRow {
    return (self.dirStack.count > 0);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return self.defaultsItems.count;
    return self.fileItems.count + ([self hasParentRow] ? 1 : 0);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"storagecell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
        cell.detailTextLabel.textColor = VConsoleSecondaryLabelColor();
        cell.detailTextLabel.numberOfLines = 1;
    }
    // 存储页文本跟随系统字号；必须每次重设，否则复用池里的旧 cell 会带着旧字号
    cell.textLabel.font = VConsoleScaledFont(13, UIFontWeightRegular);
    cell.detailTextLabel.font = VConsoleScaledFont(11, UIFontWeightRegular);
    if (indexPath.section == 0) {
        NSDictionary *d = self.defaultsItems[indexPath.row];
        cell.textLabel.text = d[@"key"];
        cell.detailTextLabel.text = d[@"value"];
        cell.imageView.image = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        // 无障碍：UserDefaults 键值行，点击看完整值
        cell.isAccessibilityElement = YES;
        cell.accessibilityLabel = [NSString stringWithFormat:@"键 %@，值 %@", d[@"key"], d[@"value"]];
        cell.accessibilityHint = @"轻点查看详情";
        return cell;
    }

    // 返回上级行（子目录第一行）
    if ([self hasParentRow] && indexPath.row == 0) {
        cell.textLabel.text = @"返回上一级";
        cell.detailTextLabel.text = @"";
        cell.imageView.image = VConsoleImageNamed(@"chevron.left.circle");
        cell.imageView.tintColor = VConsoleSecondaryLabelColor();
        cell.accessoryType = UITableViewCellAccessoryNone;
        // 无障碍：返回上级目录
        cell.isAccessibilityElement = YES;
        cell.accessibilityLabel = @"返回上一级";
        cell.accessibilityHint = @"轻点返回上一级目录";
        return cell;
    }

    NSDictionary *f = self.fileItems[indexPath.row - ([self hasParentRow] ? 1 : 0)];
    BOOL isDir = [f[@"isDir"] boolValue];
    cell.textLabel.text = f[@"name"];
    cell.detailTextLabel.text = isDir ? @"目录" : [NSString stringWithFormat:@"文件 · %@", f[@"size"]];
    cell.imageView.image = VConsoleImageNamed(isDir ? @"folder.fill" : @"doc");
    cell.imageView.tintColor = isDir ? VConsoleBlueColor() : VConsoleSecondaryLabelColor();
    cell.accessoryType = isDir ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
    // 无障碍：目录行进入浏览、文件行看详情
    cell.isAccessibilityElement = YES;
    if (isDir) {
        cell.accessibilityLabel = [NSString stringWithFormat:@"%@，目录", f[@"name"]];
        cell.accessibilityHint = @"轻点进入目录浏览内容";
    } else {
        cell.accessibilityLabel = [NSString stringWithFormat:@"%@，文件，%@", f[@"name"], f[@"size"]];
        cell.accessibilityHint = @"轻点查看详情";
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        NSDictionary *d = self.defaultsItems[indexPath.row];
        NSString *detail = [NSString stringWithFormat:@"%@ =\n%@", d[@"key"], d[@"raw"]];
        [self presentDetailWithTitle:d[@"key"] detail:detail];
        return;
    }

    // 返回上级
    if ([self hasParentRow] && indexPath.row == 0) {
        [self.dirStack removeLastObject];
        VConsoleHapticLight();
        [self refresh];
        return;
    }

    NSDictionary *f = self.fileItems[indexPath.row - ([self hasParentRow] ? 1 : 0)];
    if ([f[@"isDir"] boolValue]) {
        // 进入子目录
        [self.dirStack addObject:f[@"path"]];
        VConsoleHapticLight();
        [self refresh];
        return;
    }
    long long size = [f[@"sizeBytes"] longLongValue];
    if (size > kVConsoleMaxPreviewBytes) {
        [self toast:[NSString stringWithFormat:@"文件超过 %lldKB，不支持预览", kVConsoleMaxPreviewBytes / 1024]];
        return;
    }
    NSString *path = f[@"path"];
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!content) {
        content = [NSString stringWithFormat:@"(无法按 UTF-8 文本读取，可能是二进制文件)\n\n路径: %@", path];
    }
    [self presentDetailWithTitle:f[@"name"] detail:content];
}

- (void)presentDetailWithTitle:(NSString *)title detail:(NSString *)detail {
    VConsoleDetailViewController *vc = [[VConsoleDetailViewController alloc] initWithTitle:title detail:detail];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - UserDefaults 长按菜单：复制键 / 复制值 / 编辑值 / 删除键

/// 构造 UserDefaults 行（section 0）的长按菜单。越界 / 缺 key 时返回 nil（不弹菜单）。
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
- (nullable UIContextMenuConfiguration *)defaultsMenuConfigurationForRow:(NSInteger)row {
    if (@available(iOS 13.0, *)) {
    if (row < 0 || row >= (NSInteger)self.defaultsItems.count) return nil;
    NSDictionary *d = self.defaultsItems[row];
    if (![d isKindOfClass:[NSDictionary class]]) return nil;
    NSString *key = d[@"key"];
    NSString *raw = d[@"raw"];
    // 防御：key 为空的行不提供菜单（无法定位要操作哪条）
    if (![key isKindOfClass:[NSString class]] || key.length == 0) return nil;
    if (![raw isKindOfClass:[NSString class]]) raw = @"";

    __weak typeof(self) weakSelf = self;

    UIAction *copyKey = [UIAction actionWithTitle:@"复制键"
                                            image:VConsoleImageNamed(@"doc.on.doc")
                                       identifier:nil
                                          handler:^(__kindof UIAction *action) {
        [weakSelf copyKeyToPasteboard:key];
    }];

    UIAction *copyValue = [UIAction actionWithTitle:@"复制值"
                                              image:VConsoleImageNamed(@"doc.on.doc.fill")
                                         identifier:nil
                                            handler:^(__kindof UIAction *action) {
        [weakSelf copyValueToPasteboard:raw];
    }];

    UIAction *edit = [UIAction actionWithTitle:@"编辑值"
                                        image:VConsoleImageNamed(@"pencil")
                                   identifier:nil
                                      handler:^(__kindof UIAction *action) {
        [weakSelf presentEditAlertForKey:key currentValue:raw];
    }];

    UIAction *del = [UIAction actionWithTitle:@"删除键"
                                        image:VConsoleImageNamed(@"trash")
                                   identifier:nil
                                      handler:^(__kindof UIAction *action) {
        [weakSelf confirmDeleteKey:key];
    }];
    del.attributes = UIMenuElementAttributesDestructive;

    NSArray<UIAction *> *actions = @[copyKey, copyValue, edit, del];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                   previewProvider:nil
                                                    actionProvider:^__kindof UIMenu *_Nullable(NSArray<__kindof UIAction *> *_Nullable suggested) {
        return [UIMenu menuWithTitle:key children:actions];
    }];
    }
    return nil;
}
#pragma clang diagnostic pop

- (void)copyKeyToPasteboard:(NSString *)key {
    VConsoleStorageRunOnMain(^{
        [UIPasteboard generalPasteboard].string = key;
        VConsoleHapticSuccess();
        [self toast:[NSString stringWithFormat:@"已复制键 %@", key]];
    });
}

- (void)copyValueToPasteboard:(NSString *)value {
    VConsoleStorageRunOnMain(^{
        [UIPasteboard generalPasteboard].string = value;
        VConsoleHapticSuccess();
        [self toast:@"已复制值"];
    });
}

/// 编辑已有键的值。
/// 取舍说明：面板里输入的一切都按「字符串」写入 UserDefaults。原值若是 NSNumber /
/// BOOL / NSArray / NSDictionary 等非字符串类型，保存后会被覆盖成 NSString —— 这是调试
/// 面板的可接受取舍（H5 vConsole 同样以字符串编辑），因此弹窗 message 里明确提示用户。
- (void)presentEditAlertForKey:(NSString *)key currentValue:(NSString *)currentValue {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"编辑值"
                                                                  message:[NSString stringWithFormat:@"键：%@\n将以字符串写入（原类型会被覆盖为字符串）。", key]
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = currentValue;
        textField.placeholder = @"新的值";
        textField.font = [UIFont systemFontOfSize:14];
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];

    __weak typeof(self) weakSelf = self;
    __weak UIAlertController *weakAlert = alert; // 避免 alert → action → block → alert 循环引用
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__kindof UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *input = (weakAlert.textFields.count > 0) ? weakAlert.textFields.firstObject.text : nil;
        VConsoleStorageRunOnMain(^{
            [[VConsoleStorageInspector shared] setUserDefaultsValue:(input ?: @"") forKey:key];
            VConsoleHapticSuccess();
            [strongSelf toast:[NSString stringWithFormat:@"已更新 %@", key]];
            // refresh 内部会切到后台队列扫描再回主线程刷新，这里同步调用即可
            [strongSelf refresh];
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

/// 删除键：先二次确认（不可恢复），确认后才真正删除。
- (void)confirmDeleteKey:(NSString *)key {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"删除键"
                                                                  message:[NSString stringWithFormat:@"确定删除 “%@”？该操作不可恢复。", key]
                                                           preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    UIAlertAction *del = [UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(__kindof UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        VConsoleStorageRunOnMain(^{
            [[VConsoleStorageInspector shared] removeUserDefaultsObjectForKey:key];
            VConsoleHapticWarning();
            [strongSelf toast:[NSString stringWithFormat:@"已删除 %@", key]];
            [strongSelf refresh];
        });
    }];
    [alert addAction:del];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UserDefaults 新增键值

- (void)addButtonTapped {
    [self presentAddAlert];
}

/// 新增键值：键、值都非空才允许确认；键已存在会覆盖原值（message 里说明）。
- (void)presentAddAlert {
    NSString *message = @"值将以字符串写入；若键名已存在，将覆盖原值。";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"新增键值"
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        // 用 weak 捕获避免 self → alert → config block → self 的临时循环引用
        __strong typeof(weakSelf) self_ = weakSelf;
        if (!self_) return;
        textField.placeholder = @"键";
        textField.font = [UIFont systemFontOfSize:14];
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        [textField addTarget:self_ action:@selector(addFieldsChanged) forControlEvents:UIControlEventEditingChanged];
        self_.addKeyField = textField;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        __strong typeof(weakSelf) self_ = weakSelf;
        if (!self_) return;
        textField.placeholder = @"值";
        textField.font = [UIFont systemFontOfSize:14];
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        [textField addTarget:self_ action:@selector(addFieldsChanged) forControlEvents:UIControlEventEditingChanged];
        self_.addValueField = textField;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(__kindof UIAlertAction *action) {
        [weakSelf cleanupAddAlertState];
    }]];
    UIAlertAction *ok = [UIAlertAction actionWithTitle:@"新增" style:UIAlertActionStyleDefault handler:^(__kindof UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *key = VConsoleStorageTrimmed(strongSelf.addKeyField.text);
        NSString *value = strongSelf.addValueField.text ?: @"";
        [strongSelf cleanupAddAlertState];
        if (key.length == 0 || value.length == 0) return; // 理论上按钮已禁用，这里再兜底一次
        VConsoleStorageRunOnMain(^{
            [[VConsoleStorageInspector shared] setUserDefaultsValue:value forKey:key];
            VConsoleHapticSuccess();
            [strongSelf toast:[NSString stringWithFormat:@"已新增 %@", key]];
            [strongSelf refresh];
        });
    }];
    ok.enabled = NO; // 键/值都非空才可点
    self.addConfirmAction = ok;
    self.addAlertController = alert; // 供输入时动态刷新提示文案
    [alert addAction:ok];
    [self presentViewController:alert animated:YES completion:nil];
}

/// 实时开关「新增」按钮：键（去空白后）与值都非空才可用；并动态提示该键是否已存在。
- (void)addFieldsChanged {
    NSString *key = VConsoleStorageTrimmed(self.addKeyField.text);
    NSString *value = self.addValueField.text ?: @"";
    self.addConfirmAction.enabled = (key.length > 0 && value.length > 0);
    if (key.length > 0) {
        BOOL exists = [[VConsoleStorageInspector shared] userDefaultsContainsKey:key];
        self.addAlertController.message = exists
            ? @"值将以字符串写入；该键已存在，保存后将覆盖原值。"
            : @"值将以字符串写入；将新建该键。";
    } else {
        self.addAlertController.message = @"值将以字符串写入；键名输入后会提示是否已存在。";
    }
}

/// 释放新增弹窗的临时引用（弹窗消失后不再持有 alert / textField / action）。
- (void)cleanupAddAlertState {
    self.addAlertController = nil;
    self.addKeyField = nil;
    self.addValueField = nil;
    self.addConfirmAction = nil;
}

#pragma mark - 文件长按菜单：分享 / 删除

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView
    contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
                                       point:(CGPoint)point {
    if (@available(iOS 13.0, *)) {
    // section 0 = UserDefaults（复制键/复制值/编辑值/删除键），section 1 = 文件（分享/删除）
    if (indexPath.section == 0) {
        return [self defaultsMenuConfigurationForRow:indexPath.row];
    }
    if (indexPath.section != 1) return nil;
    if ([self hasParentRow] && indexPath.row == 0) return nil;
    NSDictionary *f = self.fileItems[indexPath.row - ([self hasParentRow] ? 1 : 0)];
    if ([f[@"isDir"] boolValue]) return nil;
    NSString *path = f[@"path"];
    NSString *name = f[@"name"];
    __weak typeof(self) weakSelf = self;

    NSMutableArray<UIAction *> *actions = [NSMutableArray array];
    [actions addObject:[UIAction actionWithTitle:@"分享文件"
                                            image:VConsoleImageNamed(@"square.and.arrow.up")
                                       identifier:nil
                                          handler:^(__kindof UIAction *action) {
        [weakSelf shareFilePath:path];
    }]];
    UIAction *del = [UIAction actionWithTitle:@"删除文件"
                                         image:VConsoleImageNamed(@"trash")
                                    identifier:nil
                                       handler:^(__kindof UIAction *action) {
        [weakSelf deleteFilePath:path name:name];
    }];
    del.attributes = UIMenuElementAttributesDestructive;
    [actions addObject:del];

    UIContextMenuConfiguration *cfg = [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                                                 previewProvider:nil
                                                                                  actionProvider:^__kindof UIMenu *_Nullable(NSArray<__kindof UIAction *> *_Nullable suggested) {
        return [UIMenu menuWithTitle:name children:actions];
    }];
    return cfg;
    }
    return nil;
}
#pragma clang diagnostic pop

- (void)shareFilePath:(NSString *)path {
    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]]
                                                                     applicationActivities:nil];
    // iPad 上必须指定 popover 锚点
    avc.popoverPresentationController.sourceView = self.view;
    avc.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2,
                                                              self.view.bounds.size.height / 3, 1, 1);
    [self presentViewController:avc animated:YES completion:nil];
}

- (void)deleteFilePath:(NSString *)path name:(NSString *)name {
    NSError *err = nil;
    if ([[NSFileManager defaultManager] removeItemAtPath:path error:&err]) {
        VConsoleHapticWarning();
        [self toast:[NSString stringWithFormat:@"已删除 %@", name]];
        [self refresh];
    } else {
        [self toast:[NSString stringWithFormat:@"删除失败: %@", err.localizedDescription]];
    }
}

- (void)toast:(NSString *)msg {
    // 轻量 toast：不拦截交互，自动消失
    [VConsoleToast showInView:self.view message:msg];
}

@end
