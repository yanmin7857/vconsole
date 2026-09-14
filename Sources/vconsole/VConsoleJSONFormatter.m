#import "VConsoleCompat.h"
#import "VConsoleJSONFormatter.h"

/// 默认折叠深度：0 层为根，深度达到该值的子树折叠为「… N items」占位。
/// 取 2 表示「根 + 两层子级」可见，更深的子树折叠，足以一眼看清顶层字段结构。
static const NSUInteger kVConsoleDefaultFoldDepth = 2;

#pragma mark - 折叠美化（递归构建，支持深度上限）

/// 生成指定层数的缩进（每层 2 空格）
static NSString *VConsoleIndentString(NSUInteger level) {
    return [@"" stringByPaddingToLength:level * 2 withString:@" " startingAtIndex:0];
}

/// 标量（字符串 / 数字 / 布尔 / null）的 JSON 字面量。
/// 借 NSJSONSerialization 编码单值数组再剥掉方括号，自动处理转义与 true/false，
/// 避免手写转义和布尔判断出错。
static NSString *VConsoleScalarLiteral(id value) {
    if (!value || value == (id)[NSNull null]) return @"null";
    if (![value isKindOfClass:[NSString class]] && ![value isKindOfClass:[NSNumber class]]) {
        return [value description];
    }
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[value] options:0 error:&err];
    if (data && !err) {
        NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        // 形如 ["abc"] / [123] / [true]，去掉外层方括号
        if (s.length >= 2) return [s substringWithRange:NSMakeRange(1, s.length - 2)];
    }
    return [value description];
}

static void VConsoleAppendJSONValue(id value, NSUInteger depth, NSUInteger maxDepth, NSMutableString *out);

/// 递归追加容器（字典 / 数组）。达到 maxDepth 的子树折叠为占位文本，不再展开。
static void VConsoleAppendJSONContainer(id obj, NSUInteger depth, NSUInteger maxDepth, NSMutableString *out) {
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)obj;
        NSArray<NSString *> *keys = [dict.allKeys sortedArrayUsingSelector:@selector(compare:)];
        if (keys.count == 0) { [out appendString:@"{}"]; return; }
        if (maxDepth > 0 && depth >= maxDepth) {
            [out appendFormat:@"{… %lu items}", (unsigned long)keys.count];
            return;
        }
        [out appendString:@"{\n"];
        for (NSUInteger i = 0; i < keys.count; i++) {
            // 冒号前带一个空格，与 NSJSONSerialization 的 pretty 输出对齐，
            // 保证「折叠版」与「完整版」在无内容可折叠时能够逐字节相等
            [out appendFormat:@"%@\"%@\" : ", VConsoleIndentString(depth + 1), keys[i]];
            VConsoleAppendJSONValue(dict[keys[i]], depth + 1, maxDepth, out);
            [out appendString:(i + 1 < keys.count) ? @",\n" : @"\n"];
        }
        [out appendFormat:@"%@}", VConsoleIndentString(depth)];
        return;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        NSArray *arr = (NSArray *)obj;
        if (arr.count == 0) { [out appendString:@"[]"]; return; }
        if (maxDepth > 0 && depth >= maxDepth) {
            [out appendFormat:@"[… %lu items]", (unsigned long)arr.count];
            return;
        }
        [out appendString:@"[\n"];
        for (NSUInteger i = 0; i < arr.count; i++) {
            [out appendString:VConsoleIndentString(depth + 1)];
            VConsoleAppendJSONValue(arr[i], depth + 1, maxDepth, out);
            [out appendString:(i + 1 < arr.count) ? @",\n" : @"\n"];
        }
        [out appendFormat:@"%@]", VConsoleIndentString(depth)];
        return;
    }
    [out appendString:VConsoleScalarLiteral(obj)];
}

static void VConsoleAppendJSONValue(id value, NSUInteger depth, NSUInteger maxDepth, NSMutableString *out) {
    if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
        VConsoleAppendJSONContainer(value, depth, maxDepth, out);
    } else {
        [out appendString:VConsoleScalarLiteral(value)];
    }
}

@implementation VConsoleJSONFormatter

+ (NSUInteger)defaultFoldDepth {
    return kVConsoleDefaultFoldDepth;
}

+ (NSString *)prettyJSONStringFromObject:(id)obj {
    if (!obj) return @"";
    if ([obj isKindOfClass:[NSDictionary class]] || [obj isKindOfClass:[NSArray class]]) {
        if ([NSJSONSerialization isValidJSONObject:obj]) {
            NSError *err = nil;
            // NSJSONWritingSortedKeys 需要 iOS 11+；部署目标已降到 9.0，iOS 11 以下仅美化不排序
            NSUInteger opts = NSJSONWritingPrettyPrinted;
            if (@available(iOS 11.0, *)) {
                opts |= NSJSONWritingSortedKeys;
            }
            NSData *data = [NSJSONSerialization dataWithJSONObject:obj
                                                           options:opts
                                                             error:&err];
            if (data && !err) {
                NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (s.length) return s;
            }
        }
    }
    return [obj description];
}

+ (NSString *)prettyJSONStringFromObject:(id)obj maxDepth:(NSUInteger)maxDepth {
    if (!obj) return @"";
    if (![obj isKindOfClass:[NSDictionary class]] && ![obj isKindOfClass:[NSArray class]]) {
        return [obj description];
    }
    NSMutableString *out = [NSMutableString string];
    VConsoleAppendJSONContainer(obj, 0, maxDepth, out);
    return [out copy];
}

+ (NSString *)prettyBodyIfJSON:(NSString *)body {
    if (body.length == 0) return body;
    // 先做一次轻量预判：仅当内容看起来像 JSON 时才解析，避免破坏纯文本 / HTML
    NSString *trimmed = [body stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0 || (![trimmed hasPrefix:@"{"] && ![trimmed hasPrefix:@"["])) {
        return body;
    }
    NSData *data = [body dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return body;
    NSError *err = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (!obj || err) return body;
    return [self prettyJSONStringFromObject:obj];
}

+ (NSString *)prettyBodyIfJSON:(NSString *)body maxDepth:(NSUInteger)maxDepth {
    if (body.length == 0) return body;
    NSString *trimmed = [body stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0 || (![trimmed hasPrefix:@"{"] && ![trimmed hasPrefix:@"["])) {
        return body;
    }
    NSData *data = [body dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return body;
    NSError *err = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (!obj || err) return body;
    return [self prettyJSONStringFromObject:obj maxDepth:maxDepth];
}

@end
