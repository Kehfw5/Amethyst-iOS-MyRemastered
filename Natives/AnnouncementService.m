//
//  AnnouncementService.m
//  Amethyst
//

#import "AnnouncementService.h"
#import "AnnouncementItem.h"
#import "LauncherPreferences.h"

/// 缓存有效期：30 分钟
static NSTimeInterval const kAnnouncementCacheInterval = 30 * 60;

/// 缓存键
static NSString * const kCachedAnnouncementsKey = @"cached_announcements";
static NSString * const kCachedAnnouncementsTimestampKey = @"cached_announcements_timestamp";

@implementation AnnouncementService

+ (instancetype)sharedService {
    static AnnouncementService *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AnnouncementService alloc] init];
    });
    return instance;
}

- (NSString *)apiURLString {
    // 从偏好设置读取 news_url，默认为官网 API 地址
    NSString *url = getPrefObject(@"general.news_url");
    if (url.length == 0) {
        url = @"https://website-air.weishixvn.workers.dev/api/announcements.php";
    }
    return url;
}

- (NSArray<AnnouncementItem *> *)cachedAnnouncements {
    NSData *data = [[NSUserDefaults standardUserDefaults] dataForKey:kCachedAnnouncementsKey];
    if (!data) return nil;
    NSError *error = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || !json) return nil;
    return [self parseAnnouncementsFromJSON:json];
}

- (BOOL)isCacheValid {
    NSTimeInterval timestamp = [[NSUserDefaults standardUserDefaults] doubleForKey:kCachedAnnouncementsTimestampKey];
    if (timestamp == 0) return NO;
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSince1970] - timestamp;
    return elapsed < kAnnouncementCacheInterval;
}

- (void)fetchAnnouncementsWithCompletion:(AnnouncementFetchHandler)completion {
    // 缓存有效时直接返回缓存
    if ([self isCacheValid]) {
        NSArray *cached = [self cachedAnnouncements];
        if (cached) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(cached, nil);
            });
            return;
        }
    }
    [self forceRefreshWithCompletion:completion];
}

- (void)forceRefreshWithCompletion:(AnnouncementFetchHandler)completion {
    NSString *urlString = [self apiURLString];
    NSLog(@"[Announcement]Fetching announcements from URL: %@", urlString);
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        NSLog(@"[Announcement]Invalid URL: %@", urlString);
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(@[], [NSError errorWithDomain:@"AnnouncementService" code:1 userInfo:@{NSLocalizedDescriptionKey: @"无效的公告 URL"}]);
        });
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];
    // InfinityFree 等主机有反爬虫机制，会拒绝非浏览器 User-Agent，
    // 故使用与项目内 Forge/NeoForge 安装器一致的 Safari UA 避免被拦截。
    [request setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15" forHTTPHeaderField:@"User-Agent"];
    request.timeoutInterval = 15.0;

    NSLog(@"[Announcement]Sending GET request, User-Agent: %@", @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15");

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger statusCode = ((NSHTTPURLResponse *)response).statusCode;
        NSUInteger dataLength = data ? data.length : 0;

        NSLog(@"[Announcement]Response received: HTTP %ld, data length=%lu, error=%@",
              (long)statusCode, (unsigned long)dataLength, error.localizedDescription ?: @"(none)");

        if (error || !data || statusCode != 200) {
            // 网络失败时尝试返回缓存
            NSLog(@"[Announcement]Request failed, falling back to cache. HTTP=%ld, error=%@", (long)statusCode, error);
            NSArray *cached = [self cachedAnnouncements];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(cached ?: @[], error ?: [NSError errorWithDomain:@"AnnouncementService" code:2 userInfo:@{NSLocalizedDescriptionKey: @"公告拉取失败"}]);
            });
            return;
        }

        // 输出响应体前 500 字节（用于诊断返回的是 JSON 还是 HTML 错误页）
        NSData *previewData = (dataLength > 500) ? [data subdataWithRange:NSMakeRange(0, 500)] : data;
        NSString *previewString = [[NSString alloc] initWithData:previewData encoding:NSUTF8StringEncoding];
        NSLog(@"[Announcement]Response preview (first 500 bytes):\n%@", previewString ?: @"(unable to decode as UTF-8)");

        // 检测 MIME 类型，提前识别 HTML 注入
        NSString *contentType = [((NSHTTPURLResponse *)response) valueForHTTPHeaderField:@"Content-Type"];
        NSLog(@"[Announcement]Content-Type: %@", contentType ?: @"(missing)");
        if (contentType && [contentType.lowercaseString containsString:@"text/html"]) {
            NSLog(@"[Announcement]ERROR: Server returned HTML instead of JSON! InfinityFree may be blocking the request.");
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(@[], [NSError errorWithDomain:@"AnnouncementService" code:4 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"服务器返回了 HTML 而非 JSON（HTTP %ld），可能是反爬虫机制拦截", (long)statusCode]}]);
            });
            return;
        }

        // 缓存原始 JSON 数据
        [[NSUserDefaults standardUserDefaults] setObject:data forKey:kCachedAnnouncementsKey];
        [[NSUserDefaults standardUserDefaults] setDouble:[[NSDate date] timeIntervalSince1970] forKey:kCachedAnnouncementsTimestampKey];
        [[NSUserDefaults standardUserDefaults] synchronize];

        // 解析
        NSError *parseError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        if (parseError || !json) {
            NSLog(@"[Announcement]JSON parse failed: %@", parseError);
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(@[], parseError ?: [NSError errorWithDomain:@"AnnouncementService" code:3 userInfo:@{NSLocalizedDescriptionKey: @"公告 JSON 解析失败"}]);
            });
            return;
        }

        NSArray *items = [self parseAnnouncementsFromJSON:json];
        NSLog(@"[Announcement]Successfully parsed %lu announcements", (unsigned long)items.count);
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(items, nil);
        });
    }];
    [task resume];
}

- (NSArray<AnnouncementItem *> *)parseAnnouncementsFromJSON:(NSDictionary *)json {
    NSArray *rawArray = json[@"announcements"];
    if (![rawArray isKindOfClass:[NSArray class]]) return @[];

    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *dict in rawArray) {
        AnnouncementItem *item = [AnnouncementItem itemFromDictionary:dict];
        if (item) [items addObject:item];
    }
    // 按日期降序排列
    [items sortUsingComparator:^NSComparisonResult(AnnouncementItem *a, AnnouncementItem *b) {
        return [b.date compare:a.date];
    }];
    return [items copy];
}

@end
