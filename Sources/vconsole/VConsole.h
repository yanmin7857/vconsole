//
//  VConsole.h
//  VConsole — 仿 H5 vConsole 的 iOS 原生调试面板
//
//  公开入口头文件。CocoaPods / SPM：
//      #import <VConsole/VConsole.h>
//      @import VConsole;
//
//  最简接入（AppDelegate / SceneDelegate 中任选一处，无需传 window）：
//      [VConsole start];
//  Release 构建下所有方法均为空实现，VConsoleLog* 宏编译为空语句，零运行时开销。
//

#import <UIKit/UIKit.h>
#import "VConsoleLogEntry.h"
#import "VConsoleLogger.h"

NS_ASSUME_NONNULL_BEGIN

/// NSUserDefaults 持久化键
FOUNDATION_EXPORT NSString * const VConsoleDefaultsKeyThemeIndex;      // NSInteger: 0 跟随系统 1 浅色 2 深色
FOUNDATION_EXPORT NSString * const VConsoleDefaultsKeyLevelFilter;     // NSInteger: VConsoleLogLevel 原始值
FOUNDATION_EXPORT NSString * const VConsoleDefaultsKeyNetworkEnabled;  // BOOL，默认 YES
FOUNDATION_EXPORT NSString * const VConsoleDefaultsKeyFabX;            // double: 悬浮球中心 X
FOUNDATION_EXPORT NSString * const VConsoleDefaultsKeyFabY;            // double: 悬浮球中心 Y
FOUNDATION_EXPORT NSString * const VConsoleDefaultsKeyPanelHeight;     // double: 面板高度占屏幕比例
FOUNDATION_EXPORT NSString * const VConsoleDefaultsKeyMockEnabled;     // BOOL，默认 NO

/// vConsole 统一入口。
/// 最简接入（DEBUG 构建生效，Release 自动零开销）：
///     #import <VConsole/VConsole.h>
///     [VConsole start];
/// 库会自动定位当前前台 keyWindow / 激活中的 UIWindowScene 并挂载悬浮球，
/// 宿主 App 无需手动传 window。所有能力仅在 DEBUG 构建中生效；Release 构建下
/// 所有方法均为空实现，日志宏（VConsoleLog*）也编译为空语句，不产生任何运行时开销。
@interface VConsole : NSObject

/// 一键接入（推荐）：自动定位当前前台窗口并挂载悬浮球。
/// 若调用时窗口尚未就绪（如 Scene 架构 App 在 window 创建前过早调用），
/// 会监听 UIWindowDidBecomeKeyNotification，在首个 keyWindow 出现时再挂载，
/// 调用方无需关心时序。
+ (void)start;

/// 显式接入：自行指定挂载悬浮球的 window。日常使用推荐 +start，不必手动传 window。
+ (void)attachToWindow:(nullable UIWindow *)window;

+ (void)show;
+ (void)hide;
+ (void)toggle;

@end

NS_ASSUME_NONNULL_END
