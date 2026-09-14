#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 一次成功命中 Mock 的结果
@interface VConsoleMockResult : NSObject

/// 二级路径段（如 /api/ECarSurveyAction/initSurveyInfo 中的 ECarSurveyAction），可能为空
@property (nonatomic, copy, nullable) NSString *module;
/// 最后一个路径段（action 名）
@property (nonatomic, copy) NSString *action;
/// 命中来源描述（用于日志与排查，如 "Documents/mock/mock.json"）
@property (nonatomic, copy) NSString *sourceDescription;
/// 序列化后的响应体
@property (nonatomic, strong) NSData *data;

@end

/// 本地 Mock 数据中心：按 URL 路径的三级查找机制返回本地响应。
///
/// 查找规则（优先级从高到低）：
/// 1. mock/<Action>.json        —— action 独立文件，整个文件内容即响应体
/// 2. mock/<Module>.json        —— 模块文件，JSON object 以 action 名为 key
/// 3. mock/mock.json            —— 全局文件，支持 {module: {action: resp}} 嵌套与 {action: resp} 扁平两种结构
///
/// 查找目录（按顺序）：
/// 1. <沙盒>/Documents/mock     —— 支持运行期热改（推文件后无需重编）
/// 2. App Bundle 的 mock/ 目录   —— 随包内置
///
/// 命中后由 VConsoleNetworkProtocol 直接把数据回给原请求方，不发出真实网络请求。
@interface VConsoleMockCenter : NSObject

+ (BOOL)isEnabled;
+ (void)setEnabled:(BOOL)enabled;

/// 按 URL 路径解析 module/action 并做三级查找；未命中返回 nil
+ (nullable VConsoleMockResult *)lookupForURL:(NSURL *)url;

/// 同上，但允许指定查找目录（单元测试用）
+ (nullable VConsoleMockResult *)lookupForURL:(NSURL *)url searchDirectories:(NSArray<NSString *> *)dirs;

@end

NS_ASSUME_NONNULL_END
