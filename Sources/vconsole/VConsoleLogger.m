#import "VConsoleCompat.h"
#import "VConsoleLogger.h"
#import "VConsole.h"
#import "VConsoleRedactor.h"

NSString *const VConsoleLoggerDidAddEntryNotification = @"VConsoleLoggerDidAddEntryNotification";
NSString *const VConsoleLoggerDidClearNotification = @"VConsoleLoggerDidClearNotification";

static const NSUInteger kVConsoleMaxLogEntries = 3000;
/// 通知合并窗口（秒）：窗口内的多条日志打包成一次通知，
/// 日志洪流时把主队列派发次数从 N 次降到最多 10 次/秒
static const NSTimeInterval kVConsoleNotifyCoalesceInterval = 0.1;

/// 剥离 NSLog 行首的系统前缀（日期 时间 [pid:tid] / 进程名[pid]），只保留正文
static NSString *vconsoleStripNSLogPrefix(NSString *line) {
    static NSRegularExpression *re = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        re = [NSRegularExpression regularExpressionWithPattern:
              @"^\\d{4}-\\d{2}-\\d{2}[ T]\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?"
              @"(\\s*\\[[0-9]+:[0-9]+\\]|\\s+[\\w.\\-]+\\[[0-9]+(:[0-9]+)?\\])\\s?"
              options:0 error:nil];
    });
    if (!re) return line;
    NSUInteger scanLen = MIN(line.length, (NSUInteger)120); // 前缀不会超过 120 字符
    NSTextCheckingResult *m = [re firstMatchInString:line options:0 range:NSMakeRange(0, scanLen)];
    if (!m || m.range.length == 0 || m.range.location != 0) return line;
    return [line substringFromIndex:m.range.length];
}

@interface VConsoleLogger () {
    int _logPipe[2];
}
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) NSMutableArray<VConsoleLogEntry *> *entries;
@property (nonatomic, assign) BOOL stderrCaptured;
// 通知合并：窗口内攒批，一次派发
@property (nonatomic, strong) NSMutableArray<VConsoleLogEntry *> *pendingEntries;
@property (nonatomic, assign) BOOL flushScheduled;
@end

@implementation VConsoleLogger {
    // 级别过滤只允许在 _queue 上读写（线程安全），对外通过重写的 getter/setter 同步访问
    VConsoleLogLevel _levelFilter;
}

+ (instancetype)shared {
    static VConsoleLogger *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VConsoleLogger alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.vconsole.logger", DISPATCH_QUEUE_SERIAL);
        _entries = [NSMutableArray array];
        _pendingEntries = [NSMutableArray array];
        _stderrCaptured = NO;
        // 恢复上次的级别过滤设置
        _levelFilter = (VConsoleLogLevel)[[NSUserDefaults standardUserDefaults] integerForKey:VConsoleDefaultsKeyLevelFilter];
    }
    return self;
}

- (void)log:(VConsoleLogLevel)level
    message:(NSString *)message
       file:(const char *)file
   function:(const char *)function
       line:(int)line {
    // 隐私脱敏：日志文本中的 token / 身份证 / 银行卡等敏感字段自动涂抹（默认开启）
    if (message.length && [VConsoleRedactor isEnabled]) {
        message = [VConsoleRedactor redact:message];
    }
    VConsoleLogEntry *entry = [[VConsoleLogEntry alloc] initWithLevel:level message:message];
    if (file) {
        NSString *f = [NSString stringWithUTF8String:file];
        entry.file = [f lastPathComponent];
    }
    if (function) {
        entry.function = [NSString stringWithUTF8String:function];
    }
    entry.line = line;

    dispatch_async(_queue, ^{
        entry.index = self.entries.count + 1;
        [self.entries addObject:entry];
        if (self.entries.count > kVConsoleMaxLogEntries) {
            [self.entries removeObjectsInRange:NSMakeRange(0, self.entries.count - kVConsoleMaxLogEntries)];
        }
        // 攒批派发：窗口内的多条日志合并为一次主队列通知（object 为 NSArray<VConsoleLogEntry *>）
        [self->_pendingEntries addObject:entry];
        if (!self->_flushScheduled) {
            self->_flushScheduled = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kVConsoleNotifyCoalesceInterval * NSEC_PER_SEC)),
                           self->_queue, ^{
                self->_flushScheduled = NO;
                if (self->_pendingEntries.count == 0) return;
                NSArray<VConsoleLogEntry *> *batch = [self->_pendingEntries copy];
                [self->_pendingEntries removeAllObjects];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter] postNotificationName:VConsoleLoggerDidAddEntryNotification
                                                                        object:batch];
                });
            });
        }
    });
}

- (NSArray<VConsoleLogEntry *> *)allEntries {
    __block NSArray *result = nil;
    dispatch_sync(_queue, ^{
        // 仅返回 >= 过滤级别的日志（在队列内读取 _levelFilter，避免数据竞争）
        NSMutableArray *filtered = [NSMutableArray array];
        for (VConsoleLogEntry *e in self.entries) {
            if (e.level >= self->_levelFilter) [filtered addObject:e];
        }
        result = [filtered copy];
    });
    return result;
}

- (void)setLevelFilter:(VConsoleLogLevel)level {
    dispatch_async(_queue, ^{
        self->_levelFilter = level;
        [[NSUserDefaults standardUserDefaults] setInteger:level forKey:VConsoleDefaultsKeyLevelFilter];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:VConsoleLoggerDidClearNotification object:nil];
        });
    });
}

- (VConsoleLogLevel)levelFilter {
    __block VConsoleLogLevel level = VConsoleLogLevelVerbose;
    dispatch_sync(_queue, ^{
        level = self->_levelFilter;
    });
    return level;
}

- (void)clear {
    dispatch_async(_queue, ^{
        [self.entries removeAllObjects];
        // 清空积压的待派发条目，避免 clear 之后又收到过期的 add 通知
        [self->_pendingEntries removeAllObjects];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:VConsoleLoggerDidClearNotification object:nil];
        });
    });
}

- (NSString *)exportAsString {
    NSArray *list = [self allEntries];
    NSMutableString *s = [NSMutableString string];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    for (VConsoleLogEntry *e in list) {
        [s appendFormat:@"[%@] %@ %@\n", [fmt stringFromDate:e.timestamp], e.levelName, e.message];
    }
    return [s copy];
}

#pragma mark - stderr 捕获（捕获 NSLog / fprintf）

- (void)startCapturingStderr {
    // @synchronized 保证幂等：任意线程多次调用也只会重定向一次
    @synchronized (self) {
        if (_stderrCaptured) return;
        _stderrCaptured = YES;
    }

    // 保存原 stderr：读取端创建失败时必须恢复，否则业务 NSLog 写满 64KB pipe 后永久阻塞
    int savedStderr = dup(STDERR_FILENO);
    if (pipe(_logPipe) != 0) {
        if (savedStderr >= 0) close(savedStderr);
        return;
    }
    dup2(_logPipe[1], STDERR_FILENO);
    close(_logPipe[1]);

    // DEFAULT 优先级：pipe 缓冲仅 64KB，若读取线程调度不到，
    // 业务线程的 NSLog 会阻塞在 pipe 写入上，拖慢业务代码
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // 单例常驻，直接持有 self 无泄漏风险
        FILE *stream = fdopen(self->_logPipe[0], "r");
        if (!stream) {
            // 打开读取端失败：恢复原 stderr，保证业务日志仍能正常输出
            if (savedStderr >= 0) { dup2(savedStderr, STDERR_FILENO); close(savedStderr); }
            close(self->_logPipe[0]);
            return;
        }
        char *line = NULL;
        size_t len = 0;
        ssize_t n;
        while ((n = getline(&line, &len, stream)) > 0) {
            NSString *text = [[NSString alloc] initWithBytes:line
                                                       length:n
                                                     encoding:NSUTF8StringEncoding];
            text = [text stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
            if (text.length == 0) continue;
            // 剥离 NSLog 系统前缀（时间戳/pid/tid），列表只留正文
            text = vconsoleStripNSLogPrefix(text);
            [self log:VConsoleLogLevelInfo
              message:[@"[NSLog] " stringByAppendingString:text]
                 file:NULL
             function:NULL
                 line:0];
        }
        free(line);
        fclose(stream);
        // 读取循环退出（进程关闭前的极端场景）：同样恢复，避免留下死管道
        if (savedStderr >= 0) { dup2(savedStderr, STDERR_FILENO); close(savedStderr); }
    });
}

@end
