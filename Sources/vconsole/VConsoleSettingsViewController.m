#import "VConsoleCompat.h"
#import "VConsoleSettingsViewController.h"
#import "VConsoleLogger.h"
#import "VConsoleNetworkLogger.h"
#import "VConsole.h"
#import "VConsoleMockCenter.h"
#import "VConsoleCrashReporter.h"
#import "VConsoleRedactor.h"
#import "VConsoleToast.h"
#import "VConsoleUICommon.h"
#import <Photos/Photos.h>

/// 「功能」区行号：新增行时只改这两处，避免 cellForRow 与 didSelectRow 用魔数走偏
static const NSInteger kVConsoleSettingsRowSlowThreshold = 4;  // 慢请求阈值
static const NSInteger kVConsoleSettingsRowCrash        = 5;  // 崩溃/异常捕获
static const NSInteger kVConsoleSettingsRowRedaction    = 6;  // 隐私脱敏
static const NSInteger kVConsoleSettingsRowShake        = 7;  // 摇一摇唤起
static const NSInteger kVConsoleSettingsRowClearAll     = 8;  // 清空全部数据

@interface VConsoleSettingsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, assign) NSInteger themeIndex;   // 0 跟随 1 浅色 2 深色
@property (nonatomic, assign) NSInteger levelIndex;   // VConsoleLogLevel
@end

@implementation VConsoleSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"设置";
    self.view.backgroundColor = VConsoleBackgroundColor();

    // 恢复持久化的设置（跨启动保留）
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.themeIndex = [defaults integerForKey:VConsoleDefaultsKeyThemeIndex];
    if (self.themeIndex < 0 || self.themeIndex > 2) self.themeIndex = 0;
    self.levelIndex = [[VConsoleLogger shared] levelFilter]; // VConsoleLogger init 时已从持久化恢复

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    // 自动行高：字号调大后固定 44 会截断文本
    _tableView.estimatedRowHeight = 44;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    [self.view addSubview:_tableView];
    [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = YES;
    [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;
    [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;

    // 系统字号变化：行高要重算，且 cell 字体是每次 cellForRow 重设的，reloadData 即可
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onContentSizeChanged:)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)onContentSizeChanged:(NSNotification *)note {
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"外观";
        case 1: return @"日志过滤级别";
        case 2: return @"功能";
        default: return @"";
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3;
    if (section == 1) return 5;
    return 9; // 网络抓包 / Mock / 导出相册 / 导出文件 / 慢请求阈值 / 崩溃捕获 / 隐私脱敏 / 摇一摇 / 清空全部数据
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != 2) return nil;
    return @"Mock 文件查找目录：Documents/mock 或 Bundle 内 mock/。\n"
           @"三级查找：Action.json > 模块.json（按 action 为 key）> mock.json（全局）。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // 「慢请求阈值」要在右侧显示当前值，需要 Value1 样式；其余行用 Default。
    // 两种样式各用一套复用池，避免混用导致 detailTextLabel 残留。
    BOOL needsValue = (indexPath.section == 2 && indexPath.row == kVConsoleSettingsRowSlowThreshold);
    NSString *cid = needsValue ? @"setcell.value1" : @"setcell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:(needsValue ? UITableViewCellStyleValue1 : UITableViewCellStyleDefault)
                                      reuseIdentifier:cid];
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.textLabel.textColor = VConsoleLabelColor(); // 复用 cell 时重置（清空数据行为红色）
    // 设置页文本跟随系统字号；必须每次重设，否则复用池里的旧 cell 会带着旧字号
    cell.textLabel.font = VConsoleFontForTextStyle(UIFontTextStyleBody);
    cell.textLabel.numberOfLines = 0;
    if (cell.detailTextLabel) {
        cell.detailTextLabel.font = VConsoleFontForTextStyle(UIFontTextStyleBody);
    }

    if (indexPath.section == 0) {
        NSArray *titles = @[@"跟随系统", @"浅色模式", @"深色模式"];
        cell.textLabel.text = titles[indexPath.row];
        if (indexPath.row == self.themeIndex) cell.accessoryType = UITableViewCellAccessoryCheckmark;
        // 无障碍：外观主题选项，当前生效项加 Selected trait
        cell.isAccessibilityElement = YES;
        cell.accessibilityLabel = titles[indexPath.row];
        cell.accessibilityHint = @"轻点切换外观主题";
        cell.accessibilityTraits = (indexPath.row == self.themeIndex)
            ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
    } else if (indexPath.section == 1) {
        NSArray *titles = @[@"Verbose (全部)", @"Debug", @"Info", @"Warn", @"Error"];
        cell.textLabel.text = titles[indexPath.row];
        if (indexPath.row == self.levelIndex) cell.accessoryType = UITableViewCellAccessoryCheckmark;
        // 无障碍：日志过滤级别选项，当前生效项加 Selected trait
        cell.isAccessibilityElement = YES;
        cell.accessibilityLabel = titles[indexPath.row];
        cell.accessibilityHint = @"轻点设置日志过滤级别";
        cell.accessibilityTraits = (indexPath.row == self.levelIndex)
            ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
    } else {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"网络抓包";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [[VConsoleNetworkLogger shared] isEnabled];
            [sw addTarget:self action:@selector(toggleNetwork:) forControlEvents:UIControlEventValueChanged];
            // 无障碍：开关自身会播报开/关，这里只补 hint；cell 保持默认以便状态被朗读
            sw.isAccessibilityElement = YES;
            sw.accessibilityHint = @"轻点开启或关闭网络请求抓包";
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Mock 数据（本地响应）";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [VConsoleMockCenter isEnabled];
            [sw addTarget:self action:@selector(toggleMock:) forControlEvents:UIControlEventValueChanged];
            // 无障碍：开关自身会播报开/关，这里只补 hint
            sw.isAccessibilityElement = YES;
            sw.accessibilityHint = @"轻点开启或关闭本地 Mock 响应";
            cell.accessoryView = sw;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"导出日志到相册";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            // 无障碍：可点选项
            cell.isAccessibilityElement = YES;
            cell.accessibilityLabel = @"导出日志到相册";
            cell.accessibilityHint = @"轻点将日志导出为图片保存到相册";
            cell.accessibilityTraits = UIAccessibilityTraitButton;
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"导出日志文件（分享）";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            // 无障碍：可点选项
            cell.isAccessibilityElement = YES;
            cell.accessibilityLabel = @"导出日志文件（分享）";
            cell.accessibilityHint = @"轻点导出日志文件并分享";
            cell.accessibilityTraits = UIAccessibilityTraitButton;
        } else if (indexPath.row == kVConsoleSettingsRowSlowThreshold) {
            cell.textLabel.text = @"慢请求阈值";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f ms", VConsoleSlowRequestThresholdMs()];
            cell.detailTextLabel.textColor = VConsoleSecondaryLabelColor();
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            // 无障碍：把当前阈值并入口播 label（Value1 样式的 detail 不单独朗读）
            cell.isAccessibilityElement = YES;
            cell.accessibilityLabel = [NSString stringWithFormat:@"慢请求阈值，当前 %.0f 毫秒", VConsoleSlowRequestThresholdMs()];
            cell.accessibilityHint = @"轻点设置慢请求阈值";
            cell.accessibilityTraits = UIAccessibilityTraitButton;
        } else if (indexPath.row == kVConsoleSettingsRowCrash) {
            cell.textLabel.text = @"崩溃/异常捕获";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [VConsoleCrashReporter isEnabled];
            [sw addTarget:self action:@selector(toggleCrash:) forControlEvents:UIControlEventValueChanged];
            sw.isAccessibilityElement = YES;
            sw.accessibilityHint = @"轻点开启或关闭崩溃/异常/卡顿捕获";
            cell.accessoryView = sw;
        } else if (indexPath.row == kVConsoleSettingsRowRedaction) {
            cell.textLabel.text = @"隐私脱敏";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [VConsoleRedactor isEnabled];
            [sw addTarget:self action:@selector(toggleRedaction:) forControlEvents:UIControlEventValueChanged];
            sw.isAccessibilityElement = YES;
            sw.accessibilityHint = @"轻点开启或关闭敏感字段涂抹";
            cell.accessoryView = sw;
        } else if (indexPath.row == kVConsoleSettingsRowShake) {
            cell.textLabel.text = @"摇一摇唤起";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:VConsoleDefaultsKeyShakeEnabled];
            [sw addTarget:self action:@selector(toggleShake:) forControlEvents:UIControlEventValueChanged];
            sw.isAccessibilityElement = YES;
            sw.accessibilityHint = @"轻点开启或关闭摇一摇切换面板";
            cell.accessoryView = sw;
        } else {
            cell.textLabel.text = @"清空全部数据（日志+网络）";
            cell.textLabel.textColor = VConsoleRedColor();
            cell.accessoryType = UITableViewCellAccessoryNone;
            // 无障碍：危险操作也要朗读清楚，让 VoiceOver 用户知道点了会清空
            cell.isAccessibilityElement = YES;
            cell.accessibilityLabel = @"清空全部数据（日志+网络）";
            cell.accessibilityHint = @"轻点清空全部日志与网络记录，操作不可撤销";
            cell.accessibilityTraits = UIAccessibilityTraitButton;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        self.themeIndex = indexPath.row;
        [self applyTheme];
        [[NSUserDefaults standardUserDefaults] setInteger:indexPath.row forKey:VConsoleDefaultsKeyThemeIndex];
        [tableView reloadData];
    } else if (indexPath.section == 1) {
        self.levelIndex = indexPath.row;
        // setLevelFilter 内部已持久化，并派发通知让日志面板刷新
        [[VConsoleLogger shared] setLevelFilter:(VConsoleLogLevel)indexPath.row];
        [tableView reloadData];
    } else if (indexPath.row == 2) {
        [self saveLogsToAlbum];
    } else if (indexPath.row == 3) {
        [self exportLogAsFile];
    } else if (indexPath.row == kVConsoleSettingsRowSlowThreshold) {
        [self chooseSlowThreshold];
    } else if (indexPath.row == kVConsoleSettingsRowCrash) {
        [self toggleCrash:nil];
    } else if (indexPath.row == kVConsoleSettingsRowRedaction) {
        [self toggleRedaction:nil];
    } else if (indexPath.row == kVConsoleSettingsRowShake) {
        [self toggleShake:nil];
    } else if (indexPath.row == kVConsoleSettingsRowClearAll) {
        [self clearAllData];
    }
}

- (void)applyTheme {
    if (@available(iOS 13.0, *)) {
        UIUserInterfaceStyle style = UIUserInterfaceStyleUnspecified;
        if (self.themeIndex == 1) style = UIUserInterfaceStyleLight;
        else if (self.themeIndex == 2) style = UIUserInterfaceStyleDark;
        // 面板在独立 window 上，直接改该 window 即可，不影响宿主 App
        self.view.window.overrideUserInterfaceStyle = style;
    }
    // < iOS 13：无暗色模式，主题覆盖忽略
}

- (void)toggleNetwork:(UISwitch *)sender {
    if (sender.isOn) [[VConsoleNetworkLogger shared] enable];
    else [[VConsoleNetworkLogger shared] disable];
    // 持久化，下次启动 VConsole 按该值决定是否开启抓包
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:VConsoleDefaultsKeyNetworkEnabled];
}

- (void)toggleMock:(UISwitch *)sender {
    [VConsoleMockCenter setEnabled:sender.isOn];
    if (sender.isOn) {
        VConsoleHapticSuccess();
        [self toast:@"Mock 已开启：命中本地文件时直接返回本地数据"];
    } else {
        VConsoleHapticLight();
    }
}

- (void)toggleCrash:(UISwitch *)sender {
    BOOL on = sender ? sender.isOn : ![VConsoleCrashReporter isEnabled];
    [VConsole setCrashReportingEnabled:on];
    [self.tableView reloadData];
    [self toast:on ? @"崩溃捕获已开启" : @"崩溃捕获已关闭"];
}

- (void)toggleRedaction:(UISwitch *)sender {
    BOOL on = sender ? sender.isOn : ![VConsoleRedactor isEnabled];
    [VConsole setRedactionEnabled:on];
    [self.tableView reloadData];
    [self toast:on ? @"隐私脱敏已开启" : @"隐私脱敏已关闭"];
}

- (void)toggleShake:(UISwitch *)sender {
    BOOL on = sender ? sender.isOn : ![[NSUserDefaults standardUserDefaults] boolForKey:VConsoleDefaultsKeyShakeEnabled];
    [VConsole setShakeToToggleEnabled:on];
    [self.tableView reloadData];
    [self toast:on ? @"摇一摇唤起已开启" : @"摇一摇唤起已关闭"];
}

#pragma mark - 导出相册

- (void)saveLogsToAlbum {
    if (@available(iOS 14.0, *)) {
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly];
        if (status == PHAuthorizationStatusNotDetermined) {
            [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly
                                                       handler:^(PHAuthorizationStatus s) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (s == PHAuthorizationStatusAuthorized) [self doSaveToAlbum];
                    else [self toast:@"未获得相册权限，无法保存"];
                });
            }];
        } else if (status == PHAuthorizationStatusAuthorized) {
            [self doSaveToAlbum];
        } else {
            [self toast:@"相册权限被拒绝，请在系统设置中开启"];
        }
    } else {
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
        if (status == PHAuthorizationStatusNotDetermined) {
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus s) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (s == PHAuthorizationStatusAuthorized) [self doSaveToAlbum];
                    else [self toast:@"未获得相册权限，无法保存"];
                });
            }];
        } else if (status == PHAuthorizationStatusAuthorized) {
            [self doSaveToAlbum];
        } else {
            [self toast:@"相册权限被拒绝，请在系统设置中开启"];
        }
    }
}

- (void)doSaveToAlbum {
    NSString *text = [[VConsoleLogger shared] exportAsString];
    if (text.length == 0) {
        [self toast:@"暂无日志可导出"];
        return;
    }
    NSMutableString *s = [NSMutableString string];
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        // 简单换行折行，长行截断（fast enumeration 变量不可变，复制到局部 __strong 变量处理）
        __strong NSString *seg = line;
        while (seg.length > 120) {
            [s appendFormat:@"%@\n", [seg substringToIndex:120]];
            seg = [seg substringFromIndex:120];
        }
        [s appendFormat:@"%@\n", seg];
    }
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.lineSpacing = 3;
    // 刻意不跟随动态字体：这是往固定 600pt 宽的画布上画导出图，
    // 字号变大会让行数暴涨、超出画布范围。跟随只会破坏导出产物。
    NSAttributedString *as = [[NSAttributedString alloc] initWithString:s
                                                               attributes:@{NSFontAttributeName: [UIFont fontWithName:@"Menlo" size:9] ?: [UIFont systemFontOfSize:9],
                                                                            NSParagraphStyleAttributeName: ps}];
    CGSize maxSize = CGSizeMake(600, CGFLOAT_MAX);
    CGRect bounds = [as boundingRectWithSize:maxSize
                                      options:NSStringDrawingUsesLineFragmentOrigin
                                      context:nil];
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = 2;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(600, bounds.size.height + 40)
                                                                        format:fmt];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef cg = ctx.CGContext;
        CGContextSetFillColorWithColor(cg, [UIColor whiteColor].CGColor);
        CGContextFillRect(cg, CGRectMake(0, 0, 600, bounds.size.height + 40));
        [as drawWithRect:CGRectMake(10, 20, 580, bounds.size.height)
                  options:NSStringDrawingUsesLineFragmentOrigin
                  context:nil];
    }];
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHAssetChangeRequest *req = [PHAssetChangeRequest creationRequestForAssetFromImage:img];
        req.creationDate = [NSDate date];
    } completionHandler:^(BOOL success, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err) [self toast:[NSString stringWithFormat:@"保存失败: %@", err.localizedDescription]];
            else [self toast:@"已保存到相册"];
        });
    }];
}

#pragma mark - 导出文件 / 清空数据

/// 导出日志为 .log 文本文件，走系统分享（AirDrop / 文件 / 微信等）
- (void)exportLogAsFile {
    NSString *text = [[VConsoleLogger shared] exportAsString];
    if (text.length == 0) {
        [self toast:@"暂无日志可导出"];
        return;
    }
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *name = [NSString stringWithFormat:@"vconsole-log-%@.log", [fmt stringFromDate:[NSDate date]]];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    if (![text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
        [self toast:@"写入临时文件失败"];
        return;
    }
    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]]
                                                                     applicationActivities:nil];
    // iPad 上 ActivityController 必须 popover 展示
    avc.popoverPresentationController.sourceView = self.view;
    avc.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, 60, 1, 1);
    [self presentViewController:avc animated:YES completion:nil];
}

/// 慢请求阈值选择：用 alert 而不是 actionSheet，省掉 iPad 上 popover 锚点的一堆麻烦
- (void)chooseSlowThreshold {
    NSTimeInterval current = VConsoleSlowRequestThresholdMs();
    NSArray<NSNumber *> *options = @[@500.0, @1000.0, @2000.0, @3000.0];
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"慢请求阈值"
                                                                message:@"耗时超过该阈值的请求会在网络列表中标记"
                                                         preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    for (NSNumber *n in options) {
        NSTimeInterval ms = n.doubleValue;
        // 当前生效项加 ✓；浮点用容差比较，避免持久化往返后出现 999.999999 之类的误判
        BOOL isCurrent = (ms >= current - 0.5) && (ms <= current + 0.5);
        NSString *title = [NSString stringWithFormat:@"%.0f ms%@", ms, isCurrent ? @" ✓" : @""];
        [ac addAction:[UIAlertAction actionWithTitle:title
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
            VConsoleSetSlowRequestThresholdMs(ms);
            VConsoleHapticLight();
            [weakSelf.tableView reloadData];
            [weakSelf toast:[NSString stringWithFormat:@"慢请求阈值已设为 %.0f ms", ms]];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

/// 一键清空日志与网络记录（带二次确认）
- (void)clearAllData {
    // 条数取未过滤的全量：这里删的是全部，不是面板上当前筛选出来的那些
    NSUInteger logCount = [[VConsoleLogger shared] allEntries].count;
    NSUInteger netCount = [[VConsoleNetworkLogger shared] entries].count;
    if (logCount + netCount == 0) {
        [self toast:@"暂无数据可清空"];
        return;
    }
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"清空全部数据？"
                                                                message:[NSString stringWithFormat:@"将删除 %lu 条日志、%lu 条网络记录，此操作不可撤销。",
                                                                         (unsigned long)logCount, (unsigned long)netCount]
                                                         preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"清空"
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *action) {
        VConsoleHapticWarning();
        [[VConsoleLogger shared] clear];
        [[VConsoleNetworkLogger shared] clear];
        [weakSelf toast:@"已清空日志与网络记录"];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)toast:(NSString *)msg {
    // 轻量 toast：不拦截交互，自动消失
    [VConsoleToast showInView:self.view message:msg];
}

@end
