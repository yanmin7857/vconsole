#import "VConsoleCompat.h"
#import "VConsoleSystemInfo.h"
#import <UIKit/UIKit.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>

@implementation VConsoleSystemInfo

+ (NSString *)deviceModel {
    struct utsname systemInfo;
    uname(&systemInfo);
    return [NSString stringWithUTF8String:systemInfo.machine];
}

+ (long long)freeDiskBytes {
    NSError *err = nil;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory()
                                                                                  error:&err];
    if (err) return 0;
    return [attrs[NSFileSystemFreeSize] longLongValue];
}

+ (long long)totalDiskBytes {
    NSError *err = nil;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory()
                                                                                  error:&err];
    if (err) return 0;
    return [attrs[NSFileSystemSize] longLongValue];
}

+ (NSArray<NSDictionary *> *)systemInfoItems {
    UIDevice *device = [UIDevice currentDevice];
    NSBundle *bundle = [NSBundle mainBundle];
    NSProcessInfo *proc = [NSProcessInfo processInfo];

    // 不开启 monitoring 时 batteryLevel 恒为 -1
    [device setBatteryMonitoringEnabled:YES];

    double totalMemoryMB = proc.physicalMemory / (1024.0 * 1024.0);
    CGSize screenSize = UIScreen.mainScreen.bounds.size;
    CGFloat scale = UIScreen.mainScreen.scale;

    long long freeDisk = [self freeDiskBytes];
    long long totalDisk = [self totalDiskBytes];

    float battery = device.batteryLevel;
    NSString *batteryText;
    if (battery < 0) {
        batteryText = @"未知";
    } else {
        batteryText = [NSString stringWithFormat:@"%.0f%%%@",
                       battery * 100,
                       device.batteryState == UIDeviceBatteryStateCharging ? @" (充电中)" : @""];
    }

    NSArray *items = @[
        @{@"title": @"App 名称", @"value": bundle.infoDictionary[@"CFBundleDisplayName"] ?: bundle.infoDictionary[@"CFBundleName"] ?: @""},
        @{@"title": @"Bundle Identifier", @"value": bundle.bundleIdentifier ?: @""},
        @{@"title": @"App 版本", @"value": [NSString stringWithFormat:@"%@ (%@)", bundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"", bundle.infoDictionary[@"CFBundleVersion"] ?: @""]},
        @{@"title": @"设备型号", @"value": [self deviceModel]},
        @{@"title": @"系统版本", @"value": [NSString stringWithFormat:@"%@ %@", device.systemName, device.systemVersion]},
        @{@"title": @"设备名称", @"value": device.name},
        @{@"title": @"屏幕分辨率", @"value": [NSString stringWithFormat:@"%.0f x %.0f @%.0fx", screenSize.width * scale, screenSize.height * scale, scale]},
        @{@"title": @"屏幕尺寸(pt)", @"value": [NSString stringWithFormat:@"%.0f x %.0f", screenSize.width, screenSize.height]},
        @{@"title": @"物理内存", @"value": [NSString stringWithFormat:@"%.0f MB", totalMemoryMB]},
        @{@"title": @"磁盘可用", @"value": [NSString stringWithFormat:@"%.1f GB", freeDisk / (1024.0 * 1024.0 * 1024.0)]},
        @{@"title": @"磁盘总量", @"value": [NSString stringWithFormat:@"%.1f GB", totalDisk / (1024.0 * 1024.0 * 1024.0)]},
        @{@"title": @"系统语言", @"value": [NSLocale preferredLanguages].firstObject ?: @""},
        @{@"title": @"时区", @"value": [[NSTimeZone localTimeZone] name]},
        @{@"title": @"UUID", @"value": device.identifierForVendor.UUIDString ?: @""},
        @{@"title": @"电量", @"value": batteryText},
    ];
    return items;
}

@end
