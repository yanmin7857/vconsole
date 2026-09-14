#import "VConsoleCompat.h"
#import "VConsoleMockCenter.h"
#import "VConsole.h"

@implementation VConsoleMockResult
@end

@implementation VConsoleMockCenter

#pragma mark - 开关（持久化）

+ (BOOL)isEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:VConsoleDefaultsKeyMockEnabled];
}

+ (void)setEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:VConsoleDefaultsKeyMockEnabled];
}

#pragma mark - 默认查找目录

+ (NSArray<NSString *> *)defaultSearchDirectories {
    NSMutableArray *dirs = [NSMutableArray array];
    // Documents/mock：运行期可热改（通过文件 App / Xcode 推文件即时生效）
    NSString *docs = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/mock"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:docs]) [dirs addObject:docs];
    // Bundle 内 mock 目录（folder reference 方式集成时位于 resourcePath/mock）
    NSString *bundleMock = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"mock"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:bundleMock]) [dirs addObject:bundleMock];
    return dirs;
}

#pragma mark - 路径解析

/// 从 URL path 中解析 module / action。
/// 约定：最后一个路径段为 action，倒数第二段为 module（不足两段时 module 为空）。
+ (void)parseURL:(NSURL *)url module:(NSString **)module action:(NSString **)action {
    NSString *m = nil, *a = nil;
    @try {
        NSArray<NSString *> *raw = url.pathComponents ?: @[];
        NSMutableArray<NSString *> *comps = [NSMutableArray array];
        for (NSString *c in raw) {
            if (c.length > 0 && ![c isEqualToString:@"/"]) [comps addObject:c];
        }
        if (comps.count >= 1) a = comps.lastObject;
        if (comps.count >= 2) m = comps[comps.count - 2];
    } @catch (NSException *e) {
        // 路径解析异常按未命中处理
    }
    if (module) *module = m;
    if (action) *action = a;
}

#pragma mark - 三级查找

+ (nullable VConsoleMockResult *)lookupForURL:(NSURL *)url {
    return [self lookupForURL:url searchDirectories:[self defaultSearchDirectories]];
}

+ (nullable VConsoleMockResult *)lookupForURL:(NSURL *)url searchDirectories:(NSArray<NSString *> *)dirs {
    NSString *module = nil, *action = nil;
    [self parseURL:url module:&module action:&action];
    if (action.length == 0) return nil;

    NSFileManager *fm = [NSFileManager defaultManager];

    // 工具：读取 JSON 文件并解析（失败返回 nil）
    NSData * (^readFile)(NSString *) = ^NSData *(NSString *path) {
        if (![fm fileExistsAtPath:path]) return nil;
        return [NSData dataWithContentsOfFile:path];
    };

    for (NSString *dir in dirs) {
        // ---- 第 1 级：mock/<Action>.json，整个文件即响应 ----
        NSString *actionPath = [dir stringByAppendingPathComponent:
                                [NSString stringWithFormat:@"%@.json", action]];
        NSData *d1 = readFile(actionPath);
        if (d1) {
            // 校验是合法 JSON（避免把随手放进去的坏文件当响应）
            if ([NSJSONSerialization JSONObjectWithData:d1 options:0 error:nil]) {
                VConsoleMockResult *r = [[VConsoleMockResult alloc] init];
                r.module = module;
                r.action = action;
                r.data = d1;
                r.sourceDescription = [NSString stringWithFormat:@"%@/%@.json", [dir lastPathComponent], action];
                return r;
            }
        }

        if (module.length == 0) continue;

        // ---- 第 2 级：mock/<Module>.json，object 以 action 为 key ----
        NSString *modulePath = [dir stringByAppendingPathComponent:
                                [NSString stringWithFormat:@"%@.json", module]];
        NSData *d2 = readFile(modulePath);
        if (d2) {
            NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:d2 options:0 error:nil];
            if ([obj isKindOfClass:[NSDictionary class]]) {
                id resp = obj[action];
                if (resp && [NSJSONSerialization isValidJSONObject:@[resp]]) {
                    VConsoleMockResult *r = [[VConsoleMockResult alloc] init];
                    r.module = module;
                    r.action = action;
                    r.data = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
                    r.sourceDescription = [NSString stringWithFormat:@"%@/%@.json → %@",
                                           [dir lastPathComponent], module, action];
                    return r;
                }
            }
        }

        // ---- 第 3 级：mock/mock.json 全局文件 ----
        NSString *globalPath = [dir stringByAppendingPathComponent:@"mock.json"];
        NSData *d3 = readFile(globalPath);
        if (d3) {
            NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:d3 options:0 error:nil];
            if ([obj isKindOfClass:[NSDictionary class]]) {
                // 优先 {module: {action: resp}} 嵌套结构
                id nested = obj[module];
                id resp = nil;
                if ([nested isKindOfClass:[NSDictionary class]]) resp = nested[action];
                // 兜底 {action: resp} 扁平结构
                if (!resp) resp = obj[action];
                if (resp && [NSJSONSerialization isValidJSONObject:@[resp]]) {
                    VConsoleMockResult *r = [[VConsoleMockResult alloc] init];
                    r.module = module;
                    r.action = action;
                    r.data = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
                    r.sourceDescription = [NSString stringWithFormat:@"%@/mock.json → %@%@",
                                           [dir lastPathComponent], module ?: @"",
                                           nested ? [NSString stringWithFormat:@"/%@", action] : action];
                    return r;
                }
            }
        }
    }
    return nil;
}

@end
