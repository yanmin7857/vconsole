#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 与 H5 vConsole System 面板一致：设备 / 系统 / App 基础信息。
@interface VConsoleSystemInfo : NSObject

+ (NSArray<NSDictionary *> *)systemInfoItems;

@end

NS_ASSUME_NONNULL_END
