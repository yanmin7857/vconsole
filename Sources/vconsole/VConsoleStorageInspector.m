#import "VConsoleCompat.h"
#import "VConsoleStorageInspector.h"
#import <WebKit/WebKit.h>
#import <Security/Security.h>

@implementation VConsoleStorageInspector

+ (instancetype)shared {
    static VConsoleStorageInspector *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VConsoleStorageInspector alloc] init];
    });
    return instance;
}

- (NSArray<NSDictionary *> *)userDefaultsItems {
    NSDictionary *dict = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    NSArray *keys = [dict.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *key in keys) {
        id value = dict[key];
        [items addObject:@{
            @"key": key,
            @"value": [VConsoleStorageInspector describeValue:value],
            @"raw": [NSString stringWithFormat:@"%@", value],
        }];
    }
    return items;
}

#pragma mark - UserDefaults 写入

- (void)setUserDefaultsValue:(id)value forKey:(NSString *)key {
    if (key.length == 0) return;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (value) {
        [ud setObject:value forKey:key];
    } else {
        [ud removeObjectForKey:key];
    }
    // synchronize 在 iOS 12+ 已是"尽力而为"，但保留调用可确保本次写入尽快落盘，
    // 且保证随后 dictionaryRepresentation 一定读得到新值。
    [ud synchronize];
}

- (void)removeUserDefaultsObjectForKey:(NSString *)key {
    if (key.length == 0) return;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud removeObjectForKey:key];
    [ud synchronize];
}

- (BOOL)userDefaultsContainsKey:(NSString *)key {
    if (key.length == 0) return NO;
    return ([[NSUserDefaults standardUserDefaults] objectForKey:key] != nil);
}

- (NSArray<NSDictionary *> *)sandboxFileItems {
    NSArray *dirs = @[
        [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"],
        [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"],
        [NSHomeDirectory() stringByAppendingPathComponent:@"tmp"],
    ];
    NSMutableArray *items = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in dirs) {
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:dir];
        NSString *sub;
        NSUInteger count = 0;
        while ((sub = [enumerator nextObject]) && count < 200) {
            count++;
            NSString *full = [dir stringByAppendingPathComponent:sub];
            NSDictionary *attrs = [fm attributesOfItemAtPath:full error:nil];
            BOOL isDir = [attrs[NSFileType] isEqualToString:NSFileTypeDirectory];
            long long size = [attrs[NSFileSize] longLongValue];
            [items addObject:@{
                @"path": full,
                @"name": [sub lastPathComponent],
                @"isDir": @(isDir),
                @"size": [NSString stringWithFormat:@"%lld B", size],
                @"sizeBytes": @(size),
            }];
        }
    }
    return items;
}

- (NSArray<NSDictionary *> *)sandboxRootItems {
    NSArray *names = @[@"Documents", @"Library", @"tmp"];
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *name in names) {
        NSString *full = [NSHomeDirectory() stringByAppendingPathComponent:name];
        [items addObject:@{
            @"path": full,
            @"name": name,
            @"isDir": @YES,
            @"size": @"-",
            @"sizeBytes": @0,
        }];
    }
    return items;
}

- (NSArray<NSDictionary *> *)fileItemsInDirectory:(NSString *)dirPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *names = [fm contentsOfDirectoryAtPath:dirPath error:nil];
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *name in names) {
        NSString *full = [dirPath stringByAppendingPathComponent:name];
        NSDictionary *attrs = [fm attributesOfItemAtPath:full error:nil];
        if (!attrs) continue; // 读取期间被删除的文件直接跳过
        BOOL isDir = [attrs[NSFileType] isEqualToString:NSFileTypeDirectory];
        long long size = [attrs[NSFileSize] longLongValue];
        [items addObject:@{
            @"path": full,
            @"name": name,
            @"isDir": @(isDir),
            @"size": isDir ? @"-" : [NSString stringWithFormat:@"%lld B", size],
            @"sizeBytes": @(size),
        }];
    }
    // 目录在前、文件在后，同类按名称排序（文件浏览器惯例）
    [items sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        BOOL ad = [a[@"isDir"] boolValue], bd = [b[@"isDir"] boolValue];
        if (ad != bd) return ad ? NSOrderedAscending : NSOrderedDescending;
        return [a[@"name"] compare:b[@"name"] options:NSCaseInsensitiveSearch];
    }];
    return items;
}

+ (NSString *)describeValue:(id)value {
    if (!value) return @"(null)";
    if ([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSDictionary class]]) {
        NSError *err = nil;
        NSData *d = [NSJSONSerialization dataWithJSONObject:value
                                                    options:NSJSONWritingPrettyPrinted
                                                      error:&err];
        if (d) return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        return [value description];
    }
    if ([value isKindOfClass:[NSData class]]) {
        return [NSString stringWithFormat:@"<Data %lu bytes>", (unsigned long)[(NSData *)value length]];
    }
    return [value description];
}

#pragma mark - WebView 数据

- (void)fetchWebViewDataWithCompletion:(void (^)(NSArray<NSDictionary *> *items))completion {
    NSMutableArray *items = [NSMutableArray array];
    WKWebsiteDataStore *store = [WKWebsiteDataStore defaultDataStore];
    [store.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        for (NSHTTPCookie *c in cookies) {
            [items addObject:@{@"kind": @"cookie",
                               @"name": c.name ?: @"",
                               @"domain": c.domain ?: @"",
                               @"masked": @"<redacted>"}];
        }
        [store fetchDataRecordsOfTypes:[NSSet setWithObject:WKWebsiteDataTypeLocalStorage]
                      completionHandler:^(NSArray<WKWebsiteDataRecord *> *records) {
            for (WKWebsiteDataRecord *r in records) {
                [items addObject:@{@"kind": @"localStorage", @"host": r.displayName ?: @""}];
            }
            if (completion) completion([items copy]);
        }];
    }];
}

#pragma mark - Keychain

- (NSArray<NSDictionary *> *)keychainItems {
    NSMutableArray *items = [NSMutableArray array];
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecReturnAttributes: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
    };
    CFTypeRef result = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (st == errSecSuccess && result) {
        NSArray *arr = (__bridge_transfer NSArray *)result;
        for (NSDictionary *d in arr) {
            if (![d isKindOfClass:[NSDictionary class]]) continue;
            [items addObject:@{
                @"kind": @"keychain",
                @"service": (d[(__bridge id)kSecAttrService] ?: @""),
                @"account": (d[(__bridge id)kSecAttrAccount] ?: @""),
                @"accessGroup": (d[(__bridge id)kSecAttrAccessGroup] ?: @""),
            }];
        }
        if (items.count > 200) [items removeObjectsInRange:NSMakeRange(200, items.count - 200)];
    }
    return [items copy];
}

@end
