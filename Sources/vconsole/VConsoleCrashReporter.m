//
//  VConsoleCrashReporter.m
//  全局崩溃 / 异常 / 主线程卡顿捕获实现
//

#import "VConsoleCompat.h"
#import "VConsoleCrashReporter.h"
#import "VConsoleLogger.h"
#import <signal.h>
#import <execinfo.h>
#import <unistd.h>
#import <fcntl.h>
#import <CoreFoundation/CoreFoundation.h>

#pragma mark - 静态状态

static BOOL gEnabled = YES;
static int gCrashFD = -1;                                  // 崩溃文件描述符（install 时预开，handler 内仅 write）
static NSUncaughtExceptionHandler *gPrevExceptionHandler = NULL;
static volatile CFAbsoluteTime gLastMainTick = 0;          // 主 RunLoop 最近一次活跃时刻
static volatile BOOL gANRReported = NO;                    // 当前卡顿是否已上报（避免刷屏）
static const NSTimeInterval kVConsoleANRThreshold = 2.0;   // 主线程无响应超过该秒数即记卡顿

static NSString *vcsCrashPath(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"vconsole-last-crash.log"];
}

static NSString *vcsSignalName(int sig) {
    switch (sig) {
        case SIGABRT: return @"SIGABRT";
        case SIGSEGV: return @"SIGSEGV";
        case SIGBUS:  return @"SIGBUS";
        case SIGILL:  return @"SIGILL";
        case SIGFPE:  return @"SIGFPE";
        case SIGTRAP: return @"SIGTRAP";
        default:      return [NSString stringWithFormat:@"%d", sig];
    }
}

#pragma mark - 崩溃文件写入（信号安全：仅用 write()）

static void vcsWriteCrashFile(NSString *report) {
    if (gCrashFD < 0) return;
    const char *c = report.UTF8String;
    if (!c) return;
    size_t len = strlen(c);
    ssize_t off = 0;
    while (off < (ssize_t)len) {
        ssize_t w = write(gCrashFD, c + off, len - (size_t)off);
        if (w <= 0) break;
        off += w;
    }
}

static NSString *vcsBuildReport(NSString *type, NSString *detail, NSArray<NSString *> *frames) {
    NSMutableString *s = [NSMutableString string];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    [s appendFormat:@"[%@] %@\n%@\n--- 调用栈 ---\n", type, [fmt stringFromDate:[NSDate date]], detail];
    for (NSString *f in frames) [s appendFormat:@"%@\n", f];
    return s;
}

#pragma mark - 入面板（best-effort，仅异常路径调用，信号路径只落盘）

static void vcsLogCrash(NSString *msg, NSArray<NSString *> *frames) {
    NSMutableString *full = [msg mutableCopy];
    if (frames.count) {
        [full appendString:@"\n"];
        NSUInteger cap = MIN(frames.count, 40);
        for (NSUInteger i = 0; i < cap; i++) [full appendFormat:@"  %@\n", frames[i]];
    }
    [[VConsoleLogger shared] log:VConsoleLogLevelError
                          message:[full copy]
                             file:NULL
                         function:NULL
                             line:0];
}

#pragma mark - 异常 Handler

static void vcs_exception_handler(NSException *exception) {
    NSArray<NSString *> *frames = exception.callStackSymbols ?: @[];
    NSString *detail = [NSString stringWithFormat:@"%@\n%@", exception.name, exception.reason];
    vcsWriteCrashFile(vcsBuildReport(@"UncaughtException", detail, frames));
    vcsLogCrash([NSString stringWithFormat:@"[CRASH] %@: %@", exception.name, exception.reason], frames);
    if (gPrevExceptionHandler) gPrevExceptionHandler(exception);
}

#pragma mark - 信号 Handler（最小安全操作）

static void vcs_signal_handler(int sig) {
    void *frames[64];
    int n = backtrace(frames, 64);
    char **syms = backtrace_symbols(frames, n);
    NSMutableString *stack = [NSMutableString string];
    for (int i = 0; i < n; i++) {
        if (syms[i]) [stack appendFormat:@"%s\n", syms[i]];
    }
    if (syms) free(syms);
    NSString *detail = [NSString stringWithFormat:@"Signal %@ (%d)", vcsSignalName(sig), sig];
    vcsWriteCrashFile(vcsBuildReport(@"Signal", detail, [stack componentsSeparatedByString:@"\n"]));
    // 恢复默认处理并重新触发，保留系统原始崩溃行为（进程终止）
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = SIG_DFL;
    sigemptyset(&sa.sa_mask);
    sigaction(sig, &sa, NULL);
    raise(sig);
}

#pragma mark - 主线程心跳 + watchdog

static void vcsMainTick(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info) {
    gLastMainTick = CFAbsoluteTimeGetCurrent();
}

static void vcsInstallMainTick(void) {
    CFRunLoopRef rl = CFRunLoopGetMain();
    CFRunLoopObserverContext ctx = {0, NULL, NULL, NULL, NULL};
    CFRunLoopObserverRef obs = CFRunLoopObserverCreate(NULL,
                                                      kCFRunLoopBeforeWaiting | kCFRunLoopAfterWaiting,
                                                      true, 0, &vcsMainTick, &ctx);
    CFRunLoopAddObserver(rl, obs, kCFRunLoopCommonModes);
    CFRelease(obs);
    gLastMainTick = CFAbsoluteTimeGetCurrent();
}

static void vcsWatchdogLoop(void) {
    while (YES) {
        [NSThread sleepForTimeInterval:0.5];
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        NSTimeInterval idle = now - gLastMainTick;
        if (idle >= kVConsoleANRThreshold) {
            if (!gANRReported) {
                gANRReported = YES;
                NSString *msg = [NSString stringWithFormat:@"[ANR] 主线程卡顿 %.0f ms（主 RunLoop 长时间无响应）",
                                 idle * 1000.0];
                [[VConsoleLogger shared] log:VConsoleLogLevelWarn
                                      message:msg
                                         file:NULL
                                     function:NULL
                                         line:0];
            }
        } else {
            gANRReported = NO;
        }
    }
}

#pragma mark - 公开实现

@implementation VConsoleCrashReporter

+ (instancetype)shared {
    static VConsoleCrashReporter *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VConsoleCrashReporter alloc] init];
    });
    return instance;
}

+ (void)setEnabled:(BOOL)enabled {
    gEnabled = enabled;
}
+ (BOOL)isEnabled {
    return gEnabled;
}

+ (void)install {
    if (!gEnabled) return;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gCrashFD = open(vcsCrashPath().UTF8String, O_WRONLY | O_CREAT | O_TRUNC, 0644);

        // 1) 未捕获异常
        gPrevExceptionHandler = NSGetUncaughtExceptionHandler();
        NSSetUncaughtExceptionHandler(&vcs_exception_handler);

        // 2) 原生信号
        int sigs[] = {SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP};
        for (int i = 0; i < 6; i++) {
            struct sigaction sa;
            memset(&sa, 0, sizeof(sa));
            sa.sa_handler = &vcs_signal_handler;
            sigemptyset(&sa.sa_mask);
            sa.sa_flags = 0;
            sigaction(sigs[i], &sa, NULL);
        }

        // 3) 主线程心跳 + watchdog
        vcsInstallMainTick();
        [NSThread detachNewThreadWithBlock:^{
            vcsWatchdogLoop();
        }];
    });
}

+ (void)replayLastCrashIfAny {
    NSString *path = vcsCrashPath();
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) return;
    NSString *content = [NSString stringWithContentsOfFile:path
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil];
    [fm removeItemAtPath:path error:nil];
    if (content.length == 0) return;
    if (content.length > 8000) {
        content = [[content substringToIndex:8000] stringByAppendingString:@"\n…(已截断)"];
    }
    [[VConsoleLogger shared] log:VConsoleLogLevelError
                          message:[@"[上次崩溃现场]\n" stringByAppendingString:content]
                             file:NULL
                         function:NULL
                             line:0];
}

@end
