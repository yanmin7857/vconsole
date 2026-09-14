#import "VConsoleCompat.h"
#import "VConsoleNetworkEntry.h"

@implementation VConsoleNetworkEntry {
    // 列表滚动热点的展示文本缓存：字段在记录前已填充完毕，懒加载一次即可
    NSString *_durationTextCache;
    NSString *_statusTextCache;
}

- (NSString *)durationText {
    if (!_durationTextCache) {
        // %.0f 对恰为 .5 的值走银行家舍入（1234.5 → 1234），这里按常规四舍五入展示
        _durationTextCache = [NSString stringWithFormat:@"%ld ms", (long)round(self.durationMs)];
    }
    return _durationTextCache;
}

- (NSString *)statusText {
    if (!_statusTextCache) {
        NSString *s = self.error ? @"ERROR" : [NSString stringWithFormat:@"%ld", (long)self.statusCode];
        if (self.mocked) s = [s stringByAppendingString:@" · MOCK"];
        if (self.fromWeb) s = [s stringByAppendingString:@" · H5"];
        _statusTextCache = s;
    }
    return _statusTextCache;
}

#pragma mark - cURL 导出

/// shell 单引号转义：' → '\''（关闭引号 + 转义引号 + 重开引号）
static NSString *vconsoleShellEscape(NSString *s) {
    return [s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
}

- (NSString *)curlCommand {
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"curl -X %@ '%@'", self.method, vconsoleShellEscape(self.url ?: @"")];
    // 只跳过 curl 自身管理的头；Content-Type/Accept 必须保留，
    // 否则 JSON POST 复现时服务端会按默认 form-urlencoded 拒绝
    NSArray<NSString *> *skipHeaders = @[@"Accept-Encoding", @"Content-Length", @"Host", @"Connection"];
    for (NSString *k in self.requestHeaders) {
        if ([skipHeaders containsObject:k]) continue;
        [s appendFormat:@" \\\n  -H '%@: %@'",
         vconsoleShellEscape(k), vconsoleShellEscape(self.requestHeaders[k])];
    }
    if (self.requestBody.length > 0) {
        [s appendFormat:@" \\\n  --data-raw '%@'", vconsoleShellEscape(self.requestBody)];
    }
    return s;
}

@end
