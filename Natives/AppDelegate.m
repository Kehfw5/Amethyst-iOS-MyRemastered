#import "AppDelegate.h"
#import "SceneDelegate.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
#import "AFNetworking.h"
#import "MinecraftResourceDownloadTask.h"
#import "AnalyticsService.h"

// SurfaceViewController
extern dispatch_group_t fatalExitGroup;

@interface AppDelegate ()
@property (nonatomic, copy) void (^backgroundURLSessionCompletionHandler)(void);
@end

@implementation AppDelegate

#pragma mark - UISceneSession lifecycle

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    // Called when a new scene session is being created.
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}

- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
    // Called when the user discards a scene session.
}

// 使用 SceneDelegate 架构时，application:didFinishLaunchingWithOptions: 仍然会被调用，
// 只是不再负责创建 window（window 由 SceneDelegate 创建）。在此初始化 AnalyticsService。
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 初始化匿名统计服务并启动心跳定时器（内部会递增 launcher_opens）
    [[AnalyticsService sharedService] startMonitoring];
    return YES;
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // 进程即将退出时尝试发送离线上报（best-effort，不阻塞）
    [[AnalyticsService sharedService] reportOffline];
    if (fatalExitGroup != nil) {
        dispatch_group_leave(fatalExitGroup);
        fatalExitGroup = nil;
    }
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // 进入后台时尝试发送离线上报。SceneDelegate 的 sceneDidEnterBackground 也会触发
    // 暂停游戏，但 AnalyticsService 的 reportOffline 是幂等的（先 stopMonitoring 再发送）。
    [[AnalyticsService sharedService] reportOffline];
}

#pragma mark - Background URL Session

- (void)application:(UIApplication *)application handleEventsForBackgroundURLSession:(NSString *)identifier completionHandler:(void (^)(void))completionHandler {
    if (![identifier isEqualToString:kMinecraftResourceDownloadBackgroundSessionIdentifier]) {
        if (completionHandler) {
            completionHandler();
        }
        return;
    }

    self.backgroundURLSessionCompletionHandler = completionHandler;

    AFURLSessionManager *manager = [MinecraftResourceDownloadTask sharedBackgroundSessionManager];
    __weak typeof(self) weakSelf = self;
    [manager setDidFinishEventsForBackgroundURLSessionBlock:^(NSURLSession *session) {
        if (weakSelf.backgroundURLSessionCompletionHandler) {
            weakSelf.backgroundURLSessionCompletionHandler();
            weakSelf.backgroundURLSessionCompletionHandler = nil;
        }
    }];
}

#pragma mark - Orientation Support

- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    // Force landscape only
    return UIInterfaceOrientationMaskLandscape;
}

@end
