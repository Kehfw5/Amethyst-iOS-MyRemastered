//
//  AnalyticsService.h
//  Amethyst
//
//  匿名使用统计服务
//  负责设备信息采集、5 分钟心跳上报、MC 版本级追踪、崩溃上报、启动器开启计数。
//  所有上报均可通过 general.analytics_enabled 偏好开关关闭。
//  device_id 在首次调用时生成 UUID 并持久化到 NSUserDefaults，后续保持不变。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AnalyticsService : NSObject

+ (instancetype)sharedService;

/// 开始监测（启动心跳定时器，递增启动器开启计数）
- (void)startMonitoring;

/// 停止监测（停止心跳定时器）
- (void)stopMonitoring;

/// 记录 MC 启动
/// @param version MC 版本号（如 "1.20.1"）
- (void)recordMCLaunch:(NSString *)version;

/// 记录 MC 退出（计算游戏时长）
- (void)recordMCExit;

/// 记录崩溃
/// @param crashType 崩溃类型（如 "SIGSEGV"、"NSException"）
/// @param stackTrace 堆栈信息
- (void)recordCrash:(NSString *)crashType stack:(NSString *)stackTrace;

/// 发送离线上报（best-effort，不阻塞退出）
- (void)reportOffline;

@end

NS_ASSUME_NONNULL_END
