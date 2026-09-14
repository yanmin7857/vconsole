#import "VConsoleCompat.h"
#import "VConsoleLogEntry.h"
#import "VConsoleJSONFormatter.h"

/// 列表摘要最多保留的行数：超出则截断并提示进详情查看，
/// 避免单条几十行的 JSON 把日志流撑成上千 pt 的巨型 cell。
static const NSUInteger kVConsoleMaxSummaryLines = 8;

@implementation VConsoleLogEntry {
    BOOL _looksJSONChecked;
    BOOL _looksJSON;
    NSString *_displayMessage;
    NSString *_summaryMessage;
}

- (instancetype)initWithLevel:(VConsoleLogLevel)level message:(NSString *)message {
    self = [super init];
    if (self) {
        _timestamp = [NSDate date];
        _level = level;
        _message = message ?: @"";
        _levelName = [VConsoleLogEntry nameForLevel:level];
        _line = 0;
    }
    return self;
}

+ (NSString *)nameForLevel:(VConsoleLogLevel)level {
    switch (level) {
        case VConsoleLogLevelVerbose: return @"VERBOSE";
        case VConsoleLogLevelDebug:   return @"DEBUG";
        case VConsoleLogLevelInfo:    return @"INFO";
        case VConsoleLogLevelWarn:    return @"WARN";
        case VConsoleLogLevelError:   return @"ERROR";
    }
    return @"LOG";
}

#pragma mark - 展示缓存（懒加载，3000 条日志滚动时避免反复 JSON 解析）

- (BOOL)messageLooksLikeJSON {
    if (!_looksJSONChecked) {
        _looksJSONChecked = YES;
        NSString *t = [_message stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        _looksJSON = ([t hasPrefix:@"{"] || [t hasPrefix:@"["]);
    }
    return _looksJSON;
}

- (NSString *)displayMessage {
    if (!_displayMessage) {
        if (self.messageLooksLikeJSON) {
            _displayMessage = [VConsoleJSONFormatter prettyBodyIfJSON:_message] ?: _message;
        } else {
            _displayMessage = _message;
        }
    }
    return _displayMessage;
}

- (NSString *)summaryMessage {
    if (!_summaryMessage) {
        NSString *full = self.displayMessage;
        NSArray<NSString *> *lines = [full componentsSeparatedByString:@"\n"];
        if (lines.count <= kVConsoleMaxSummaryLines) {
            // 8 行以内（含无换行的普通日志）原样展示，行为与改动前一致
            _summaryMessage = full;
        } else {
            NSArray<NSString *> *head = [lines subarrayWithRange:NSMakeRange(0, kVConsoleMaxSummaryLines)];
            _summaryMessage = [NSString stringWithFormat:@"%@\n… 共 %lu 行，点击查看详情",
                               [head componentsJoinedByString:@"\n"], (unsigned long)lines.count];
        }
    }
    return _summaryMessage;
}

@end
