//
//  AnalyticsService.m
//  Amethyst
//

#import "AnalyticsService.h"
#import "LauncherPreferences.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <sys/sysctl.h>
#import <unistd.h>

/// 心跳间隔：5 分钟（300 秒）
static NSTimeInterval const kAnalyticsHeartbeatInterval = 300.0;

/// 默认上报 URL
static NSString * const kAnalyticsDefaultURL = @"https://air-api.vercel.app/api/report.php";

/// NSUserDefaults 键
static NSString * const kAnalyticsDeviceIDKey = @"analytics_device_id";
static NSString * const kAnalyticsMCVersionStatsKey = @"analytics_mc_version_stats";
static NSString * const kAnalyticsLauncherOpensKey = @"analytics_launcher_opens";
static NSString * const kAnalyticsTotalCrashesKey = @"analytics_total_crashes";

/// 当前 MC 版本与启动时间戳（仅内存，进程退出后丢失，故配合 reportOffline 持久化）
static NSString * const kAnalyticsCurrentMCVersionKey = @"analytics_current_mc_version";
static NSString * const kAnalyticsMCLaunchTimestampKey = @"analytics_mc_launch_timestamp";

@interface AnalyticsService ()
/// GCD 心跳定时器源
@property (nonatomic, strong) dispatch_source_t heartbeatTimer;
/// 心跳定时器所在的后台队列
@property (nonatomic, assign) dispatch_queue_t heartbeatQueue;
@end

@implementation AnalyticsService

#pragma mark - Singleton

+ (instancetype)sharedService {
    static AnalyticsService *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AnalyticsService alloc] init];
    });
    return instance;
}

#pragma mark - 上报 URL 解析

- (NSString *)apiURLString {
    // 优先使用 general.analytics_url（如果有），其次将 general.news_url 中的
    // "/api/announcements.json" 替换为 "/api/report.php"，最后回退到默认值。
    NSString *url = getPrefObject(@"general.analytics_url");
    if (url.length > 0) {
        return url;
    }
    NSString *newsURL = getPrefObject(@"general.news_url");
    if (newsURL.length > 0) {
        NSString *replaced = [newsURL stringByReplacingOccurrencesOfString:@"/api/announcements.php"
                                                                withString:@"/api/report.php"];
        if (![replaced isEqualToString:newsURL]) {
            return replaced;
        }
    }
    return kAnalyticsDefaultURL;
}

#pragma mark - 偏好开关

- (BOOL)isAnalyticsEnabled {
    // 默认开启：getPrefBool 在键未设置时返回 NO，但 PLPreferences.m 的默认字典中
    // 显式声明 analytics_enabled = @YES，所以正常流程下首启即为 YES。
    return getPrefBool(@"general.analytics_enabled");
}

#pragma mark - device_id 管理

- (NSString *)deviceID {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *deviceID = [defaults stringForKey:kAnalyticsDeviceIDKey];
    if (deviceID.length == 0) {
        // 首次调用时生成 UUID 并持久化
        deviceID = [[NSUUID UUID] UUIDString];
        [defaults setObject:deviceID forKey:kAnalyticsDeviceIDKey];
        [defaults synchronize];
    }
    return deviceID;
}

#pragma mark - 设备信息采集

- (NSString *)deviceModelIdentifier {
    // sysctlbyname("hw.machine", ...) 返回如 "iPhone16,2"
    size_t size = 0;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    if (size == 0) {
        return @"unknown";
    }
    char *buffer = (char *)malloc(size);
    if (!buffer) {
        return @"unknown";
    }
    int result = sysctlbyname("hw.machine", buffer, &size, NULL, 0);
    NSString *model = nil;
    if (result == 0) {
        model = [NSString stringWithUTF8String:buffer];
    }
    free(buffer);
    return model.length > 0 ? model : @"unknown";
}

- (NSString *)systemVersion {
    return [[UIDevice currentDevice] systemVersion];
}

- (NSString *)launcherVersion {
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return version.length > 0 ? version : @"unknown";
}

#pragma mark - 安装方式检测

/// 检测 TrollStore 安装特征
- (BOOL)isTrollStoreInstall {
    // TrollStore 通常带有 com.apple.developer.kernel.extended-controller 权限
    if (getEntitlementValue(@"com.apple.developer.kernel.extended-controller")) {
        return YES;
    }
    // 备选方案：检查 TrollStore 标记目录
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:@"/var/containers/Bundle/TrollStore/"]) {
        return YES;
    }
    // 与 main.m 一致的 _TrollStore 标记文件检查
    NSString *tsPath = [NSString stringWithFormat:@"%@/../_TrollStore", [[NSBundle mainBundle] bundlePath]];
    if (!access(tsPath.UTF8String, F_OK)) {
        return YES;
    }
    return NO;
}

/// 检测越狱安装
- (BOOL)isJailbrokenInstall {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:@"/var/jb"]) {
        return YES;
    }
    if ([fm fileExistsAtPath:@"/Applications/Cydia.app"]) {
        return YES;
    }
    return NO;
}

/// 检测 AltStore 安装
- (BOOL)isAltStoreInstall {
    // 检查 AltServerConnection 类是否可加载
    Class altClass = NSClassFromString(@"ALTServerConnection");
    if (altClass != nil) {
        return YES;
    }
    // 备选方案：检查 AltKit framework 是否被链接
    NSString *altKitPath = [[[[NSBundle mainBundle] privateFrameworksPath] stringByAppendingPathComponent:@"AltKit.framework"] stringByAppendingString:@"/AltKit"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:altKitPath]) {
        return YES;
    }
    return NO;
}

- (NSString *)installMethod {
    if ([self isTrollStoreInstall]) {
        return @"trollstore";
    }
    if ([self isJailbrokenInstall]) {
        return @"jailbroken";
    }
    if ([self isAltStoreInstall]) {
        return @"altstore";
    }
    return @"none";
}

#pragma mark - 原版 Amethyst 安装检测

- (BOOL)isOriginalAmethystInstalled {
    // canOpenURL 需要 Info.plist 的 LSApplicationQueriesSchemes 中声明 "amethyst"。
    // 未声明时 canOpenURL 始终返回 NO 并打印日志，但不影响其他逻辑。
    NSURL *amethystURL = [NSURL URLWithString:@"amethyst://"];
    if (!amethystURL) {
        return NO;
    }
    // UIApplication 必须在主线程调用
    if (![NSThread isMainThread]) {
        __block BOOL result = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            result = [[UIApplication sharedApplication] canOpenURL:amethystURL];
        });
        return result;
    }
    return [[UIApplication sharedApplication] canOpenURL:amethystURL];
}

#pragma mark - MC 版本级追踪

- (NSMutableDictionary *)mcVersionStats {
    NSDictionary *stats = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kAnalyticsMCVersionStatsKey];
    return [NSMutableDictionary dictionaryWithDictionary:stats ?: @{}];
}

- (void)saveMCVersionStats:(NSDictionary *)stats {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:stats forKey:kAnalyticsMCVersionStatsKey];
    [defaults synchronize];
}

- (void)recordMCLaunch:(NSString *)version {
    if (version.length == 0) {
        return;
    }
    // 递增对应版本的 launch_count
    NSMutableDictionary *stats = [self mcVersionStats];
    NSMutableDictionary *versionEntry = [NSMutableDictionary dictionaryWithDictionary:stats[version] ?: @{}];
    NSInteger launchCount = [versionEntry[@"launch_count"] integerValue];
    versionEntry[@"launch_count"] = @(launchCount + 1);
    stats[version] = versionEntry;
    [self saveMCVersionStats:stats];

    // 记录当前 MC 版本与启动时间戳（用于 recordMCExit 计算游戏时长）
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:version forKey:kAnalyticsCurrentMCVersionKey];
    [defaults setDouble:[[NSDate date] timeIntervalSince1970] forKey:kAnalyticsMCLaunchTimestampKey];
    [defaults synchronize];

    NSLog(@"[Analytics] recordMCLaunch: version=%@", version);
}

- (void)recordMCExit {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *currentVersion = [defaults stringForKey:kAnalyticsCurrentMCVersionKey];
    NSTimeInterval launchTimestamp = [defaults doubleForKey:kAnalyticsMCLaunchTimestampKey];
    if (currentVersion.length == 0 || launchTimestamp == 0) {
        // 没有记录的启动事件，直接返回
        return;
    }

    // 计算游戏时长并累加到对应版本
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval playTime = now - launchTimestamp;
    if (playTime < 0) {
        playTime = 0;
    }

    NSMutableDictionary *stats = [self mcVersionStats];
    NSMutableDictionary *versionEntry = [NSMutableDictionary dictionaryWithDictionary:stats[currentVersion] ?: @{}];
    NSInteger totalPlayTime = [versionEntry[@"play_time_seconds"] integerValue];
    versionEntry[@"play_time_seconds"] = @(totalPlayTime + (NSInteger)playTime);
    stats[currentVersion] = versionEntry;
    [self saveMCVersionStats:stats];

    // 清空当前版本和启动时间戳，避免重复计算
    [defaults removeObjectForKey:kAnalyticsCurrentMCVersionKey];
    [defaults removeObjectForKey:kAnalyticsMCLaunchTimestampKey];
    [defaults synchronize];

    NSLog(@"[Analytics] recordMCExit: version=%@ play_time=%llds", currentVersion, (long long)playTime);
}

#pragma mark - 崩溃上报

- (void)recordCrash:(NSString *)crashType stack:(NSString *)stackTrace {
    if (crashType.length == 0) {
        crashType = @"unknown";
    }
    if (stackTrace.length == 0) {
        stackTrace = @"";
    }

    // 1. 递增本地 total_crashes
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSInteger totalCrashes = [defaults integerForKey:kAnalyticsTotalCrashesKey];
    [defaults setInteger:totalCrashes + 1 forKey:kAnalyticsTotalCrashesKey];

    // 2. 递增当前 MC 版本的 crash_count（如果有 current_mc_version）
    NSString *currentVersion = [defaults stringForKey:kAnalyticsCurrentMCVersionKey];
    if (currentVersion.length > 0) {
        NSMutableDictionary *stats = [self mcVersionStats];
        NSMutableDictionary *versionEntry = [NSMutableDictionary dictionaryWithDictionary:stats[currentVersion] ?: @{}];
        NSInteger crashCount = [versionEntry[@"crash_count"] integerValue];
        versionEntry[@"crash_count"] = @(crashCount + 1);
        stats[currentVersion] = versionEntry;
        [self saveMCVersionStats:stats];
    }
    [defaults synchronize];

    NSLog(@"[Analytics] recordCrash: type=%@ mc_version=%@", crashType, currentVersion ?: @"");

    // 3. 发送崩溃上报（best-effort 异步请求，不阻塞退出）
    [self sendReportWithAction:@"crash"
                      crashType:crashType
                     crashStack:stackTrace
                      mcVersion:currentVersion ?: @""
                        sync:NO];
}

#pragma mark - 心跳定时器

- (void)startMonitoring {
    // 检查总开关
    if (![self isAnalyticsEnabled]) {
        NSLog(@"[Analytics] Analytics disabled, skip startMonitoring");
        return;
    }

    // 递增启动器开启计数
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSInteger launcherOpens = [defaults integerForKey:kAnalyticsLauncherOpensKey];
    [defaults setInteger:launcherOpens + 1 forKey:kAnalyticsLauncherOpensKey];
    [defaults synchronize];

    // 已有定时器在跑则不重复启动
    if (self.heartbeatTimer != nil) {
        return;
    }

    // 创建 GCD 定时器，在后台队列运行
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0);
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    // 5 分钟间隔，0 容差
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAnalyticsHeartbeatInterval * NSEC_PER_SEC)),
                              (uint64_t)(kAnalyticsHeartbeatInterval * NSEC_PER_SEC),
                              (uint64_t)(30 * NSEC_PER_SEC)); // 30 秒容差，省电
    __weak __typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf sendReportWithAction:@"heartbeat"
                               crashType:nil
                              crashStack:nil
                               mcVersion:nil
                                   sync:NO];
    });
    self.heartbeatQueue = queue;
    self.heartbeatTimer = timer;
    dispatch_resume(timer);

    NSLog(@"[Analytics] Heartbeat timer started (interval=%.0fs)", kAnalyticsHeartbeatInterval);
}

- (void)stopMonitoring {
    if (self.heartbeatTimer != nil) {
        dispatch_source_cancel(self.heartbeatTimer);
        self.heartbeatTimer = nil;
        self.heartbeatQueue = nil;
        NSLog(@"[Analytics] Heartbeat timer stopped");
    }
}

#pragma mark - 汇总统计

/// 从 MC 版本统计字典中计算总启动次数
- (NSInteger)totalMCLaunches {
    NSDictionary *stats = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kAnalyticsMCVersionStatsKey] ?: @{};
    NSInteger total = 0;
    for (NSDictionary *entry in stats.allValues) {
        total += [entry[@"launch_count"] integerValue];
    }
    return total;
}

/// 从 MC 版本统计字典中计算总游戏时长（秒）
- (NSInteger)totalPlayTimeSeconds {
    NSDictionary *stats = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kAnalyticsMCVersionStatsKey] ?: @{};
    NSInteger total = 0;
    for (NSDictionary *entry in stats.allValues) {
        total += [entry[@"play_time_seconds"] integerValue];
    }
    return total;
}

#pragma mark - 上报请求

- (NSDictionary *)buildCommonPayload {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSInteger launcherOpens = [defaults integerForKey:kAnalyticsLauncherOpensKey];
    NSInteger totalCrashes = [defaults integerForKey:kAnalyticsTotalCrashesKey];
    NSDictionary *mcStats = [defaults dictionaryForKey:kAnalyticsMCVersionStatsKey] ?: @{};

    return @{
        @"device_id": [self deviceID],
        @"device_model": [self deviceModelIdentifier],
        @"ios_version": [self systemVersion],
        @"launcher_version": [self launcherVersion],
        @"jailbreak_status": [self installMethod],
        @"has_original_amethyst": @([self isOriginalAmethystInstalled]),
        @"launcher_opens": @(launcherOpens),
        @"total_crashes": @(totalCrashes),
        @"total_mc_launches": @([self totalMCLaunches]),
        @"total_play_time_seconds": @([self totalPlayTimeSeconds]),
        @"mc_versions": mcStats,
        @"timestamp": @([[NSDate date] timeIntervalSince1970]),
    };
}

- (void)sendReportWithAction:(NSString *)action
                   crashType:(nullable NSString *)crashType
                  crashStack:(nullable NSString *)crashStack
                   mcVersion:(nullable NSString *)mcVersion
                       sync:(BOOL)sync {
    // 检查总开关（崩溃上报也走此路径，但崩溃场景下用户更可能希望上报，故仍受开关控制）
    if (![self isAnalyticsEnabled]) {
        return;
    }

    NSString *urlString = [self apiURLString];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        NSLog(@"[Analytics] Invalid report URL: %@", urlString);
        return;
    }

    // 构造请求体
    NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithDictionary:[self buildCommonPayload]];
    payload[@"action"] = action;
    if (crashType.length > 0) {
        payload[@"crash_type"] = crashType;
    }
    if (crashStack.length > 0) {
        payload[@"crash_stack"] = crashStack;
    }
    if (mcVersion.length > 0) {
        payload[@"mc_version"] = mcVersion;
    }

    NSError *jsonError = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonError];
    if (jsonError || !bodyData) {
        NSLog(@"[Analytics] Failed to serialize JSON: %@", jsonError);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    // InfinityFree 等主机有反爬虫机制，会拒绝非浏览器 User-Agent，
    // 故使用与项目内 Forge/NeoForge 安装器一致的 Safari UA 避免被拦截。
    [request setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15" forHTTPHeaderField:@"User-Agent"];
    [request setHTTPBody:bodyData];
    request.timeoutInterval = 10.0;

    NSLog(@"[Analytics] Sending POST to %@, action=%@, body length=%lu, sync=%d",
          urlString, action, (unsigned long)bodyData.length, sync);

    // 同步模式用于崩溃场景（进程即将退出）
    if (sync) {
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSInteger statusCode = ((NSHTTPURLResponse *)response).statusCode;
            NSLog(@"[Analytics] Sync report (%@) HTTP %ld, error=%@", action, (long)statusCode, error.localizedDescription ?: @"(none)");
            if (error || (statusCode != 200 && statusCode != 201 && statusCode != 204)) {
                NSData *preview = (data && data.length > 0) ? (data.length > 300 ? [data subdataWithRange:NSMakeRange(0, 300)] : data) : nil;
                NSString *previewStr = preview ? [[NSString alloc] initWithData:preview encoding:NSUTF8StringEncoding] : @"(no body)";
                NSLog(@"[Analytics] Sync report failed preview: %@", previewStr);
            }
            dispatch_semaphore_signal(semaphore);
        }];
        [task resume];
        // 最多等待 2 秒，避免崩溃时长时间阻塞
        dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)));
        return;
    }

    // 异步模式（心跳、崩溃 best-effort、离线上报）
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[Analytics] Report (%@) failed: %@", action, error.localizedDescription);
            return;
        }
        NSInteger statusCode = ((NSHTTPURLResponse *)response).statusCode;
        if (statusCode != 200 && statusCode != 201 && statusCode != 204) {
            NSLog(@"[Analytics] Report (%@) HTTP %ld", action, (long)statusCode);
            // 输出响应体前 300 字节用于诊断
            NSData *preview = (data && data.length > 0) ? (data.length > 300 ? [data subdataWithRange:NSMakeRange(0, 300)] : data) : nil;
            NSString *previewStr = preview ? [[NSString alloc] initWithData:preview encoding:NSUTF8StringEncoding] : @"(no body)";
            NSLog(@"[Analytics] Report (%@) response preview: %@", action, previewStr);
            // 检测 HTML 响应
            NSString *contentType = [((NSHTTPURLResponse *)response) valueForHTTPHeaderField:@"Content-Type"];
            if (contentType && [contentType.lowercaseString containsString:@"text/html"]) {
                NSLog(@"[Analytics] ERROR: Server returned HTML for report! InfinityFree may be blocking.");
            }
        } else {
            NSLog(@"[Analytics] Report (%@) success HTTP %ld", action, (long)statusCode);
        }
    }];
    [task resume];
}

#pragma mark - 离线上报

- (void)reportOffline {
    // 停止心跳定时器
    [self stopMonitoring];

    if (![self isAnalyticsEnabled]) {
        return;
    }

    // 同时尝试记录 MC 退出（用户可能在游戏中按 Home 后退出 app）
    [self recordMCExit];

    // 发送 offline 上报（best-effort，同步等待最多 2 秒）
    [self sendReportWithAction:@"offline"
                      crashType:nil
                     crashStack:nil
                      mcVersion:nil
                        sync:YES];

    NSLog(@"[Analytics] Offline report sent");
}

@end
