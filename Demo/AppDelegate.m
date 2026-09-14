#import "VConsoleCompat.h"
#import "AppDelegate.h"
#import "DemoViewController.h"
#import "VConsole.h"
#ifdef DEBUG
#import "VConsoleLogger.h"
#endif

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
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

    return YES;
}

@end
