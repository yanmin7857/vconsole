#import "VConsoleCompat.h"
#import "DemoViewController.h"
#import "DemoWebViewController.h"
#import "VConsole.h"
#import "VConsoleLogger.h"
#import "VConsoleNetworkLogger.h"

@interface DemoViewController ()
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation DemoViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"vconsole";
    self.view.backgroundColor = VConsoleBackgroundColor();

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.alignment = UIStackViewAlignmentFill;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];

    if (@available(iOS 11.0, *)) {
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:30].active = YES;
    } else {
        [stack.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:30].active = YES;
    }
    [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24].active = YES;
    [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24].active = YES;

    UILabel *title = [[UILabel alloc] init];
    title.text = @"vconsole for iOS";
    title.font = [UIFont boldSystemFontOfSize:26];
    title.textAlignment = NSTextAlignmentCenter;
    UILabel *sub = [[UILabel alloc] init];
    sub.text = @"仿 H5 vConsole 的 iOS 原生调试面板\n点击右下角绿色悬浮球打开控制台";
    sub.font = [UIFont systemFontOfSize:14];
    sub.textColor = VConsoleSecondaryLabelColor();
    sub.textAlignment = NSTextAlignmentCenter;
    sub.numberOfLines = 0;

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.text = @"状态：等待操作";
    _statusLabel.font = [UIFont systemFontOfSize:13];
    _statusLabel.textColor = VConsoleSecondaryLabelColor();
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.numberOfLines = 0;

    [stack addArrangedSubview:title];
    [stack addArrangedSubview:sub];
    [stack addArrangedSubview:[self spacer]];
    [stack addArrangedSubview:[self buttonWithTitle:@"打印测试日志" action:@selector(logDemo)]];
    [stack addArrangedSubview:[self buttonWithTitle:@"发起网络请求" action:@selector(networkDemo)]];
    [stack addArrangedSubview:[self buttonWithTitle:@"JSON 网络请求" action:@selector(jsonNetworkDemo)]];
    [stack addArrangedSubview:[self buttonWithTitle:@"JSON 日志打印" action:@selector(jsonLogDemo)]];
    [stack addArrangedSubview:[self buttonWithTitle:@"混合压力测试" action:@selector(stressDemo)]];
    [stack addArrangedSubview:[self buttonWithTitle:@"超长日志行" action:@selector(longLogDemo)]];
    [stack addArrangedSubview:[self buttonWithTitle:@"大响应体请求" action:@selector(largeResponseDemo)]];
    [stack addArrangedSubview:[self buttonWithTitle:@"WKWebView H5 测试（网络 + Console）" action:@selector(webDemo)]];
    [stack addArrangedSubview:[self spacer]];
    [stack addArrangedSubview:_statusLabel];
}

- (UIView *)spacer {
    UIView *v = [[UIView alloc] init];
    [v.heightAnchor constraintEqualToConstant:8].active = YES;
    return v;
}

- (UIButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *b;
    if (@available(iOS 15.0, *)) {
        // iOS 15+ 用 UIButtonConfiguration 替代已废弃的 contentEdgeInsets
        UIButtonConfiguration *cfg = [UIButtonConfiguration plainButtonConfiguration];
        cfg.attributedTitle = [[NSAttributedString alloc] initWithString:title
                                                              attributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:16]}];
        cfg.baseForegroundColor = [UIColor colorWithRed:0.06 green:0.55 blue:0.34 alpha:1.0];
        cfg.background.backgroundColor = [UIColor colorWithRed:0.10 green:0.72 blue:0.45 alpha:0.12];
        cfg.contentInsets = NSDirectionalEdgeInsetsMake(12, 0, 12, 0);
        b = [UIButton buttonWithConfiguration:cfg primaryAction:nil];
    } else {
        b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:title forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        [b setTitleColor:[UIColor colorWithRed:0.06 green:0.55 blue:0.34 alpha:1.0] forState:UIControlStateNormal];
        b.backgroundColor = [UIColor colorWithRed:0.10 green:0.72 blue:0.45 alpha:0.12];
        b.contentEdgeInsets = UIEdgeInsetsMake(12, 0, 12, 0);
    }
    b.layer.cornerRadius = 10;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

#pragma mark - 演示动作

- (void)logDemo {
    VConsoleLogV(@"verbose 级别日志示例");
    VConsoleLogD(@"debug 级别日志，来自 %@", NSStringFromClass([self class]));
    VConsoleLogI(@"info 级别日志：用户点击了「打印测试日志」");
    VConsoleLogW(@"warn 级别日志：这是一个警告示例");
    VConsoleLogE(@"error 级别日志：这是一个错误示例");
    self.statusLabel.text = @"已写入 5 条分级日志，打开控制台查看";
}

- (void)networkDemo {
    self.statusLabel.text = @"正在请求 https://api.github.com/zen ...";
    NSURL *url = [NSURL URLWithString:@"https://api.github.com/zen"];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                self.statusLabel.text = [NSString stringWithFormat:@"请求失败: %@", error.localizedDescription];
                VConsoleLogE(@"网络请求失败: %@", error.localizedDescription);
            } else {
                NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                self.statusLabel.text = [NSString stringWithFormat:@"请求成功: %@", s];
                VConsoleLogI(@"网络请求成功，返回 %lu 字节", (unsigned long)data.length);
            }
        });
    }];
    [task resume];
    VConsoleLogI(@"发起 GET 请求: %@", url);
}

- (void)jsonNetworkDemo {
    self.statusLabel.text = @"正在请求 https://api.github.com/repos/Tencent/vConsole ...";
    NSURL *url = [NSURL URLWithString:@"https://api.github.com/repos/Tencent/vConsole"];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                self.statusLabel.text = [NSString stringWithFormat:@"JSON 请求失败: %@", error.localizedDescription];
                VConsoleLogE(@"JSON 网络请求失败: %@", error.localizedDescription);
            } else {
                self.statusLabel.text = [NSString stringWithFormat:@"JSON 请求成功: %lu 字节（可在「网络」面板查看美化后的响应体）", (unsigned long)data.length];
                VConsoleLogI(@"JSON 网络请求成功，返回 %lu 字节", (unsigned long)data.length);
            }
        });
    }];
    [task resume];
    VConsoleLogI(@"发起 JSON GET 请求: %@", url);
}

- (void)jsonLogDemo {
    NSDictionary *sampleDict = @{
        @"name": @"vconsole",
        @"platform": @"iOS",
        @"version": @"1.0.0",
        @"features": @[@"log", @"network", @"storage"],
        @"nested": @{@"enabled": @YES, @"count": @42}
    };
    NSArray *sampleArr = @[
        @{@"id": @1, @"title": @"日志美化"},
        @{@"id": @2, @"title": @"响应体展示"}
    ];
    VConsoleLogI(@"示例 NSDictionary:");
    VConsoleLogI(@"%@", sampleDict);
    VConsoleLogD(@"示例 NSArray:");
    VConsoleLogD(@"%@", sampleArr);
    self.statusLabel.text = @"已打印 NSDictionary / NSArray 示例，打开「日志」面板查看美化后的 JSON";
}

- (void)stressDemo {
    self.statusLabel.text = @"执行混合压力测试（日志 + 网络）";
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (int i = 0; i < 20; i++) {
            VConsoleLogD(@"压力测试日志 #%d", i);
            if (i % 5 == 0) {
                NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://api.github.com/zen?r=%d", i]];
                [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                    if (e) VConsoleLogW(@"压力测试请求 #%d 失败: %@", i, e.localizedDescription);
                    else VConsoleLogD(@"压力测试请求 #%d 完成", i);
                }] resume];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.text = @"混合压力测试完成";
        });
    });
}

/// 超长日志行：验证列表长文本展示与滚动性能
- (void)longLogDemo {
    NSMutableString *s = [NSMutableString stringWithString:@"超长日志行示例（共 8000 字符）："];
    while (s.length < 8000) {
        [s appendString:@"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"];
    }
    VConsoleLogI(@"%@", s);
    self.statusLabel.text = @"已打印 8000 字符超长日志，打开「日志」面板查看";
}

/// 大响应体请求：验证网络面板大 body 的截断展示与 JSON 美化
- (void)largeResponseDemo {
    self.statusLabel.text = @"正在请求大 JSON 响应（100 条 posts，约 28KB）...";
    NSURL *url = [NSURL URLWithString:@"https://jsonplaceholder.typicode.com/posts"];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                self.statusLabel.text = [NSString stringWithFormat:@"大响应请求失败: %@", error.localizedDescription];
                VConsoleLogE(@"大响应请求失败: %@", error.localizedDescription);
            } else {
                self.statusLabel.text = [NSString stringWithFormat:@"大响应请求成功: %lu 字节（网络面板可查看截断与美化效果）", (unsigned long)data.length];
                VConsoleLogI(@"大响应请求成功，返回 %lu 字节", (unsigned long)data.length);
            }
        });
    }];
    [task resume];
    VConsoleLogI(@"发起大响应 GET 请求: %@", url);
}

/// WKWebView H5 测试演示：页面含「网络监控」与「H5 Console 测试」两组入口，
/// 网络记录回「网络」面板（带 H5 标记），console.* 打印回「日志」面板（带「· H5」前缀）
- (void)webDemo {
    [self.navigationController pushViewController:[[DemoWebViewController alloc] init] animated:YES];
}

#pragma mark - 自动演示（仅带 -vcsDemo 启动参数时触发，正常启动不受影响）

// 用于生成 README 演示动图：xcrun simctl launch booted com.vconsole.ios -vcsDemo
// 启动后自动完成「日志（原生分级）→ 网络 → 存储 → 系统 → H5 console 捕获」的完整流程，
// 供录屏；正常手动启动不会有任何自动行为。
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self runDemoIfRequested];
}

- (void)runDemoIfRequested {
    if (![[NSProcessInfo processInfo].arguments containsObject:@"-vcsDemo"]) return;

    // 时间轴（秒），用于生成 README 演示动图，四面板全覆盖。
    // 首帧刻意延后到 2.0s：录制侧在 App 就绪后再开录，避免把 iOS 桌面录进动图。
    //   2.0  清空启动噪声 + 发起真实网络请求（网络面板需要真实数据）
    //   2.6  打印 5 条原生分级日志
    //   3.2  展开面板 → 日志 Tab（原生分级着色）
    //   6.2  切到 网络 Tab（真实请求 + JSON 美化）
    //   9.0  切到 存储 Tab
    //  10.8  切到 系统 Tab
    //  12.6  收起面板
    //  13.2  进入 WKWebView H5 测试页（页面加载自动发 fetch + XHR）
    //  14.8  触发页面内 console.log/info/debug/warn/error
    //  16.2  回面板 → 日志 Tab 看「· H5」记录
    //  18.6  切到 网络 Tab 看 H5 请求记录
    void (^at)(double, dispatch_block_t) = ^(double t, dispatch_block_t block) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(t * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), block);
    };

    __block DemoWebViewController *wvc = nil;

    at(2.0, ^{
        [[VConsoleLogger shared] clear];
        [[VConsoleNetworkLogger shared] clear];
        [self jsonNetworkDemo];
        [self largeResponseDemo];
    });
    at(2.6, ^{ [self logDemo]; });
    at(3.2, ^{
        [VConsole show];
        [VConsole selectPanelTab:VConsolePanelTabLog];
    });
    at(6.2, ^{ [VConsole selectPanelTab:VConsolePanelTabNetwork]; });
    at(9.0, ^{ [VConsole selectPanelTab:VConsolePanelTabStorage]; });
    at(10.8, ^{ [VConsole selectPanelTab:VConsolePanelTabSystem]; });
    at(12.6, ^{ [VConsole hide]; });
    at(13.2, ^{
        [[VConsoleLogger shared] clear];
        wvc = [[DemoWebViewController alloc] init];
        [self.navigationController pushViewController:wvc animated:YES];
    });
    at(14.8, ^{ [wvc fireAllConsole]; });
    at(16.2, ^{
        [VConsole show];
        [VConsole selectPanelTab:VConsolePanelTabLog];
    });
    at(18.6, ^{ [VConsole selectPanelTab:VConsolePanelTabNetwork]; });
}

@end
