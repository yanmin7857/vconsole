//
//  VConsoleRedactor.m
//  隐私脱敏实现
//

#import "VConsoleCompat.h"
#import "VConsoleRedactor.h"

@interface VConsoleRedactor ()
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, strong) NSMutableArray<NSRegularExpression *> *customRules;
@property (nonatomic, strong) NSMutableArray<NSString *> *customTemplates;
@end

@implementation VConsoleRedactor

+ (instancetype)shared {
    static VConsoleRedactor *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VConsoleRedactor alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _enabled = YES;
        _customRules = [NSMutableArray array];
        _customTemplates = [NSMutableArray array];
    }
    return self;
}

+ (void)setEnabled:(BOOL)enabled {
    [VConsoleRedactor shared].enabled = enabled;
}
+ (BOOL)isEnabled {
    return [VConsoleRedactor shared].enabled;
}

/// 内置规则：一次性编译缓存。顺序即涂抹优先级。
- (NSArray<NSRegularExpression *> *)builtinRules {
    static NSArray<NSRegularExpression *> *rules = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *patterns = @[
            // Authorization 请求头整行
            @"(?i)authorization:\\s*[^\\r\\n]+",
            // JSON / 字典里的敏感键（值整段涂抹）
            @"(?i)(\"(?:authorization|access[-_]?token|refresh[-_]?token|token|secret|password|passwd|pwd|api[-_]?key|apikey|cookie)\"\\s*:\\s*\")([^\"]*)(\")",
            // Cookie 里的高敏键（sessionid/sid/token/auth/jwt…）
            @"(?i)((?:sessionid|sid|token|auth|jwt|access[-_]?token)=)[^;\\r\\n]+",
            // 身份证号（18 位，6 位地区 + 8 位生日 + 4 位序列/校验；末位校验码可为 X）
            // 用 (?<!\\d)/(?!\\d) 收窄边界，避免把 19 位银行卡的前 18 位误判为身份证
            @"(?<!\\d)(\\d{6})\\d{8}(\\d{3}[\\dX])(?!\\d)",
            // 银行卡号（16~19 位，保留前 4 后 4）
            @"(?<!\\d)(\\d{4})\\d{8,11}(\\d{4})(?!\\d)",
        ];
        NSMutableArray *arr = [NSMutableArray array];
        for (NSString *p in patterns) {
            NSError *err = nil;
            NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:p
                                                                                options:NSRegularExpressionCaseInsensitive
                                                                                  error:&err];
            if (re) [arr addObject:re];
        }
        rules = [arr copy];
    });
    return rules;
}

/// 内置规则对应的替换模板（与 builtinRules 顺序一致）。
- (NSArray<NSString *> *)builtinTemplates {
    static NSArray<NSString *> *templates = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        templates = @[
            @"Authorization: <redacted>",
            @"$1<redacted>$3",
            @"$1<redacted>",
            @"$1********$2",
            @"$1****$2",
        ];
    });
    return templates;
}

+ (NSString *)redact:(NSString *)text {
    VConsoleRedactor *r = [VConsoleRedactor shared];
    if (!r.enabled) return text;
    if (text.length == 0) return text;

    NSMutableString *out = [text mutableCopy];
    // 内置规则
    NSArray<NSRegularExpression *> *rules = [r builtinRules];
    NSArray<NSString *> *templates = [r builtinTemplates];
    for (NSUInteger i = 0; i < rules.count && i < templates.count; i++) {
        [rules[i] replaceMatchesInString:out
                                  options:0
                                    range:NSMakeRange(0, out.length)
                             withTemplate:templates[i]];
    }
    // 自定义规则
    for (NSUInteger i = 0; i < r.customRules.count; i++) {
        NSString *tpl = (i < r.customTemplates.count) ? r.customTemplates[i] : @"<redacted>";
        [r.customRules[i] replaceMatchesInString:out
                                         options:0
                                           range:NSMakeRange(0, out.length)
                                    withTemplate:tpl];
    }
    return [out copy];
}

+ (void)addCustomPattern:(NSString *)pattern replacement:(NSString *)replacement {
    NSError *err = nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                        options:NSRegularExpressionCaseInsensitive
                                                                          error:&err];
    if (!re) return;
    VConsoleRedactor *r = [VConsoleRedactor shared];
    [r.customRules addObject:re];
    [r.customTemplates addObject:(replacement ?: @"<redacted>")];
}

+ (void)resetCustomPatterns {
    VConsoleRedactor *r = [VConsoleRedactor shared];
    [r.customRules removeAllObjects];
    [r.customTemplates removeAllObjects];
}

@end
