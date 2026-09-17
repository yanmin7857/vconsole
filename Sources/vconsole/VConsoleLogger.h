#import <Foundation/Foundation.h>
#import "VConsoleLogEntry.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const VConsoleLoggerDidAddEntryNotification;
extern NSString *const VConsoleLoggerDidClearNotification;

/// 与 H5 vConsole 一致的日志面板数据源：分级采集 + 可选捕获 NSLog(stderr)。
@interface VConsoleLogger : NSObject

+ (instancetype)shared;

- (void)log:(VConsoleLogLevel)level
    message:(NSString *)message
       file:(nullable const char *)file
   function:(nullable const char *)function
       line:(int)line;

- (NSArray<VConsoleLogEntry *> *)allEntries;
/// 当前级别过滤（仅显示 >= filter 的日志）。线程安全，并跨启动持久化。
- (void)setLevelFilter:(VConsoleLogLevel)level;
- (VConsoleLogLevel)levelFilter;

- (void)clear;
/// 重定向 stderr，使 NSLog / fprintf 也能进入面板（类似 vConsole 捕获 console）。幂等，可安全多次调用。
/// 捕获的同时会把原始行写回真实 stderr，因此 Xcode 控制台仍能看到 NSLog 输出。
- (void)startCapturingStderr;
/// 是否正在捕获 stderr。
- (BOOL)isCapturingStderr;
/// 开关：是否把 NSLog / fprintf(stderr) 捕获进面板（默认 YES）。
/// 设为 NO 会恢复真实 stderr——Xcode 控制台恢复，但面板不再收 NSLog。
/// 设为 YES 等价于 startCapturingStderr（幂等）。
- (void)setCaptureStderrEnabled:(BOOL)enabled;
/// 当前开关状态。
- (BOOL)captureStderrEnabled;
/// 导出全部日志为纯文本。
- (NSString *)exportAsString;

@end

#ifdef DEBUG
#define VConsoleLogV(fmt, ...) [VConsoleLogger.shared log:VConsoleLogLevelVerbose message:[NSString stringWithFormat:fmt, ##__VA_ARGS__] file:__FILE__ function:__PRETTY_FUNCTION__ line:__LINE__]
#define VConsoleLogD(fmt, ...) [VConsoleLogger.shared log:VConsoleLogLevelDebug   message:[NSString stringWithFormat:fmt, ##__VA_ARGS__] file:__FILE__ function:__PRETTY_FUNCTION__ line:__LINE__]
#define VConsoleLogI(fmt, ...) [VConsoleLogger.shared log:VConsoleLogLevelInfo    message:[NSString stringWithFormat:fmt, ##__VA_ARGS__] file:__FILE__ function:__PRETTY_FUNCTION__ line:__LINE__]
#define VConsoleLogW(fmt, ...) [VConsoleLogger.shared log:VConsoleLogLevelWarn    message:[NSString stringWithFormat:fmt, ##__VA_ARGS__] file:__FILE__ function:__PRETTY_FUNCTION__ line:__LINE__]
#define VConsoleLogE(fmt, ...) [VConsoleLogger.shared log:VConsoleLogLevelError   message:[NSString stringWithFormat:fmt, ##__VA_ARGS__] file:__FILE__ function:__PRETTY_FUNCTION__ line:__LINE__]
#else
// Release 构建：日志宏编译为空语句，参数不求值、零运行时开销
#define VConsoleLogV(fmt, ...) ((void)0)
#define VConsoleLogD(fmt, ...) ((void)0)
#define VConsoleLogI(fmt, ...) ((void)0)
#define VConsoleLogW(fmt, ...) ((void)0)
#define VConsoleLogE(fmt, ...) ((void)0)
#endif

NS_ASSUME_NONNULL_END
