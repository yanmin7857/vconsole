#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, VConsoleLogLevel) {
    VConsoleLogLevelVerbose = 0,
    VConsoleLogLevelDebug,
    VConsoleLogLevelInfo,
    VConsoleLogLevelWarn,
    VConsoleLogLevelError,
};

@interface VConsoleLogEntry : NSObject

@property (nonatomic, assign) NSUInteger index;
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, assign) VConsoleLogLevel level;
@property (nonatomic, copy) NSString *levelName;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, copy, nullable) NSString *file;
@property (nonatomic, copy, nullable) NSString *function;
@property (nonatomic, assign) NSInteger line;

- (instancetype)initWithLevel:(VConsoleLogLevel)level message:(NSString *)message;
+ (NSString *)nameForLevel:(VConsoleLogLevel)level;

/// message 是否形如 JSON（懒加载缓存，用于列表选择等宽字体）
@property (nonatomic, readonly, assign) BOOL messageLooksLikeJSON;
/// 展示文本：JSON 时返回美化结果（懒加载缓存，避免滚动时反复解析）
@property (nonatomic, readonly, copy) NSString *displayMessage;
/// 列表用摘要：把 displayMessage 截断到前 8 行，超出补「… 共 N 行，点击查看详情」。
/// 用于避免单条巨型 JSON 把日志流撑成上千 pt 的巨型 cell。
/// 详情弹窗必须用 displayMessage 取完整内容，否则会退回「看不到具体的」。
@property (nonatomic, readonly, copy) NSString *summaryMessage;

@end

NS_ASSUME_NONNULL_END
