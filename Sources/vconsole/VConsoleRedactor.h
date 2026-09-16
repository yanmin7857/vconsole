//
//  VConsoleRedactor.h
//  vconsole — 隐私脱敏（PII / 凭证涂抹）
//
//  在网络请求/响应与日志文本中自动涂抹敏感字段：Authorization、token、密码类键值、
//  身份证号、银行卡号。默认开启，可在设置页或代码中关闭 / 追加自定义规则。
//  脱敏是非破坏性的：仅作用于「展示 / 导出」文本，原始 entry 数据不动，便于调试时按需查看。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VConsoleRedactor : NSObject

+ (instancetype)shared;

/// 全局开关（默认 YES）。关闭后 redact: 原样返回。
+ (void)setEnabled:(BOOL)enabled;
+ (BOOL)isEnabled;

/// 对文本做脱敏。enabled=NO 时直接返回原串。
+ (NSString *)redact:(NSString *)text;

/// 追加自定义脱敏规则。pattern 为标准正则；replacement 中 $1/$2 引用捕获组。
+ (void)addCustomPattern:(NSString *)pattern replacement:(NSString *)replacement;
/// 清空自定义规则（内置规则不受影响）。
+ (void)resetCustomPatterns;

@end

NS_ASSUME_NONNULL_END
