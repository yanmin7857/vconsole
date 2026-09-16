#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// App 自身 CPU 占用百分比（0~100+，多核可 >100）。失败返回 -1。
double VConsoleAppCPUUsage(void);

/// App 自身常驻内存（MB）。失败返回 -1。
double VConsoleAppMemoryMB(void);

/// 字节可读化：B / KB / MB / GB。
NSString *VConsoleFormatBytes(long long bytes);

/// 百分比格式化："12.3%"。
NSString *VConsoleFormatPercent(double percent);

NS_ASSUME_NONNULL_END
