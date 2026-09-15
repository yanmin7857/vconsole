#import "VConsoleCompat.h"
#import "AppDelegate.h"
#import "DemoViewController.h"
#import "VConsole.h"
#ifdef DEBUG
#import "VConsoleLogger.h"
#endif

@implementation AppDelegate

#pragma mark - UIApplicationDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 窗口与 rootViewController 在 scene:willConnectToSession: 中创建，
    // 必须 initWithWindowScene: 挂到系统分配的 UIWindowScene 上，否则 Scene 内 window
    // 无 rootViewController，UIKit 会在 _runWithMainScene 断言崩溃。
    return YES;
}

// iOS 13+ 多窗口/单窗口场景均由该方法提供 UISceneConfiguration，
// delegate 类名取 Info.plist 中 UISceneConfigurations 的 Default 配置（即 AppDelegate 自身）。
- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                                   options:(UISceneConnectionOptions *)options {
    return [[UISceneConfiguration alloc] initWithName:@"Default"
                                          sessionRole:connectingSceneSession.role];
}

#pragma mark - UIWindowSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];

    DemoViewController *demo = [[DemoViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:demo];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];

    // vConsole 一键接入：DEBUG 构建启用全部调试能力，Release 下为空实现
    [VConsole attachToWindow:self.window];

#ifdef DEBUG
    VConsoleLogI(@"[vconsole] 应用启动完成，调试面板已就绪");
    VConsoleLogD(@"[vconsole] 当前设备: %@", [UIDevice currentDevice].model);

    // 启动网络自检：验证 NSURLProtocol 抓包链路在真实路径上生效
    NSURL *ping = [NSURL URLWithString:@"https://api.github.com/zen"];
    [[[NSURLSession sharedSession] dataTaskWithURL:ping
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) VConsoleLogW(@"[vconsole] 启动网络自检失败: %@", err.localizedDescription);
        else VConsoleLogI(@"[vconsole] 启动网络自检成功，返回 %lu 字节", (unsigned long)data.length);
    }] resume];
#endif
}

@end
