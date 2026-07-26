//
//  AnalyticsStatsViewController.h
//  Amethyst
//
//  使用统计展示页
//  从 api/stats.php 拉取统计数据，以 UITableView 分区展示：
//  - 概览卡片（2x3 网格）
//  - 设备型号 / 系统版本 / 启动器版本 / 越狱状态 分布
//  - Minecraft 各版本统计
//  - 近期崩溃统计（7 天内）
//  - 其他统计（原版 Amethyst 安装数）
//
//  参考 AnnouncementListViewController.m 的导航栏样式（关闭按钮、标题）
//  参考 MinecraftNewsViewController.m 的网络请求和 JSON 解析风格
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AnalyticsStatsViewController : UIViewController

@end

NS_ASSUME_NONNULL_END
