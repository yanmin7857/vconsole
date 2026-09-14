#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 与 H5 vConsole Storage 面板一致：查看 UserDefaults 与沙盒文件。
@interface VConsoleStorageInspector : NSObject

+ (instancetype)shared;

/// UserDefaults（standard）中所有键值对，按 key 排序。
- (NSArray<NSDictionary *> *)userDefaultsItems;

/// 写入 UserDefaults（standard）中的一个键。
/// - Parameters:
///   - value: 要写入的值；传 nil 等价于删除该 key。
///   - key: 键名；为空字符串时本次调用被忽略。
- (void)setUserDefaultsValue:(nullable id)value forKey:(NSString *)key;

/// 删除 UserDefaults（standard）中的一个键（key 为空时被忽略）。
- (void)removeUserDefaultsObjectForKey:(NSString *)key;

/// 判断 UserDefaults（standard）中是否存在某个键（用于新增前提示「将覆盖」）。
- (BOOL)userDefaultsContainsKey:(NSString *)key;

/// 沙盒关键目录下的文件列表：Documents / Library/Caches / tmp。
- (NSArray<NSDictionary *> *)sandboxFileItems;

/// 沙盒根节点（Documents / Library / tmp），供目录导航的起始层。
- (NSArray<NSDictionary *> *)sandboxRootItems;

/// 非递归列举某个目录的内容（目录在前、文件在后，均按名称排序）。
/// 字典结构与 sandboxFileItems 一致（path/name/isDir/size/sizeBytes）。
- (NSArray<NSDictionary *> *)fileItemsInDirectory:(NSString *)dirPath;

/// 通用可读描述。
+ (NSString *)describeValue:(id)value;

@end

NS_ASSUME_NONNULL_END
