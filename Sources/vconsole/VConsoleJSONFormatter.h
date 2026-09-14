#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// JSON / 对象美化工具：将容器对象或可解析的 JSON 字符串转为易读的缩进格式。
@interface VConsoleJSONFormatter : NSObject

/// 若 obj 是 NSDictionary / NSArray，按美观 + 排序键输出；否则返回 [obj description]。
+ (NSString *)prettyJSONStringFromObject:(id)obj;

/// 尝试把 body 当 JSON 解析并美化；解析失败（纯文本 / HTML / 表单等）则原样返回。
+ (NSString *)prettyBodyIfJSON:(NSString *)body;

/// 默认折叠深度（0 层为根，超过该深度的子树折叠为「… N items」占位）。
+ (NSUInteger)defaultFoldDepth;

/// 带折叠深度的美化：超过 maxDepth 的子树折叠为「… N items」占位，
/// 便于在详情里一眼看清顶层结构。maxDepth 传 0 表示不折叠（等价完整美化）。
/// 非 NSDictionary / NSArray 时回退 [obj description]。
+ (NSString *)prettyJSONStringFromObject:(id)obj maxDepth:(NSUInteger)maxDepth;

/// prettyBodyIfJSON: 的折叠版本：先解析再按 maxDepth 折叠；解析失败原样返回。
+ (NSString *)prettyBodyIfJSON:(NSString *)body maxDepth:(NSUInteger)maxDepth;

@end

NS_ASSUME_NONNULL_END
