//
//  VConsoleCrashReporter.h
//  vconsole — 全局崩溃 / 异常 / 主线程卡顿捕获
//
//  捕获三类问题并写入日志面板（ERROR 级）与本地崩溃文件：
//   1) 未捕获的 Objective-C 异常（NSSetUncaughtExceptionHandler）
//   2) 原生信号崩溃（SIGABRT / SIGSEGV / SIGBUS / SIGILL / SIGFPE / SIGTRAP）
//   3) 主线程卡顿（watchdog 线程监测主 RunLoop 无响应）
//  信号类崩溃因只能在信号处理上下文做安全的最小操作，写入本地文件，下次启动由
//  replayLastCrashIfAny 回填到面板；异常类则尝试即时入面板 + 落盘。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VConsoleCrashReporter : NSObject

/// 安装全局捕获（幂等）。建议仅在 DEBUG 构建调用（Release 自动零开销）。
+ (void)install;
/// 开关（默认 YES）。关闭后不安装 / 卸载已安装的捕获。
+ (void)setEnabled:(BOOL)enabled;
+ (BOOL)isEnabled;
/// 启动时若有上次崩溃文件，回填一条日志（App 重启后仍能看到上次现场）。
+ (void)replayLastCrashIfAny;

@end

NS_ASSUME_NONNULL_END
