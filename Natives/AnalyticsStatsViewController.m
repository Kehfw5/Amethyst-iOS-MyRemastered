//
//  AnalyticsStatsViewController.m
//  Amethyst
//
//  使用统计展示页实现
//  数据源：general.news_url 指向的 API 根目录下的 /api/stats.php
//  URL 构造：将 general.news_url 中的 /api/announcements.json 替换为 /api/stats.php
//  默认值：https://newamethyst.ct.ws/api/stats.php
//

#import "AnalyticsStatsViewController.h"
#import "BackgroundManager.h"
#import "LauncherPreferences.h"

/// 卡片圆角
static const CGFloat kStatsCardCornerRadius = 12.0;
/// 卡片内边距
static const CGFloat kStatsCardPadding = 14.0;
/// 卡片间距
static const CGFloat kStatsCardSpacing = 10.0;
/// 分区 header 高度
static const CGFloat kStatsHeaderHeight = 38.0;

/// 分区枚举
typedef NS_ENUM(NSInteger, StatsSection) {
    StatsSectionOverview = 0,          // 概览卡片
    StatsSectionDeviceModels,          // 设备型号分布
    StatsSectionIosVersions,           // 系统版本分布
    StatsSectionLauncherVersions,      // 启动器版本分布
    StatsSectionJailbreakStatus,       // 越狱状态分布
    StatsSectionMcVersions,            // Minecraft 版本统计
    StatsSectionRecentCrashes,         // 近期崩溃统计
    StatsSectionOther,                 // 其他统计
    StatsSectionCount                  // 分区总数
};

#pragma mark - StatsOverviewCell

/// 概览卡片 Cell：2x3 网格展示 6 个核心数字
@interface StatsOverviewCell : UITableViewCell
@property (nonatomic, strong) NSArray<UILabel *> *valueLabels;
@property (nonatomic, strong) NSArray<UILabel *> *titleLabels;
@property (nonatomic, strong) NSArray<UIView *> *cardViews;
- (void)configureWithData:(NSDictionary *)overview;
@end

@implementation StatsOverviewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];

        // 6 个卡片标题（按行排列：在线用户数|总用户数 / MC启动总次数|崩溃总次数 / 游戏总时长|启动器开启次数）
        NSArray<NSString *> *titles = @[
            @"在线用户数", @"总用户数",
            @"MC启动总次数", @"崩溃总次数",
            @"游戏总时长", @"启动器开启次数"
        ];

        NSMutableArray<UILabel *> *values = [NSMutableArray array];
        NSMutableArray<UILabel *> *titleLabelArr = [NSMutableArray array];
        NSMutableArray<UIView *> *cards = [NSMutableArray array];

        // 外层纵向 stack（3 行）
        UIStackView *verticalStack = [[UIStackView alloc] init];
        verticalStack.translatesAutoresizingMaskIntoConstraints = NO;
        verticalStack.axis = UILayoutConstraintAxisVertical;
        verticalStack.distribution = UIStackViewDistributionFillEqually;
        verticalStack.spacing = kStatsCardSpacing;
        [self.contentView addSubview:verticalStack];

        for (NSInteger row = 0; row < 3; row++) {
            // 每行一个横向 stack（2 列）
            UIStackView *horizontalStack = [[UIStackView alloc] init];
            horizontalStack.axis = UILayoutConstraintAxisHorizontal;
            horizontalStack.distribution = UIStackViewDistributionFillEqually;
            horizontalStack.spacing = kStatsCardSpacing;
            [verticalStack addArrangedSubview:horizontalStack];

            for (NSInteger col = 0; col < 2; col++) {
                NSInteger idx = row * 2 + col;

                // 卡片容器
                UIView *card = [[UIView alloc] init];
                card.backgroundColor = [UIColor secondarySystemBackgroundColor];
                card.layer.cornerRadius = kStatsCardCornerRadius;
                card.layer.cornerCurve = kCACornerCurveContinuous;
                card.layer.masksToBounds = YES;
                [horizontalStack addArrangedSubview:card];

                // 数值大标签
                UILabel *valueLabel = [[UILabel alloc] init];
                valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
                valueLabel.font = [UIFont boldSystemFontOfSize:20];
                valueLabel.textColor = [UIColor labelColor];
                valueLabel.textAlignment = NSTextAlignmentCenter;
                valueLabel.text = @"-";
                [card addSubview:valueLabel];

                // 标题小标签
                UILabel *titleLabel = [[UILabel alloc] init];
                titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
                titleLabel.font = [UIFont systemFontOfSize:12];
                titleLabel.textColor = [UIColor secondaryLabelColor];
                titleLabel.textAlignment = NSTextAlignmentCenter;
                titleLabel.text = titles[idx];
                [card addSubview:titleLabel];

                [NSLayoutConstraint activateConstraints:@[
                    [valueLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:kStatsCardPadding],
                    [valueLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:6],
                    [valueLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-6],

                    [titleLabel.topAnchor constraintEqualToAnchor:valueLabel.bottomAnchor constant:4],
                    [titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:6],
                    [titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-6],
                    [titleLabel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-kStatsCardPadding],
                ]];

                [cards addObject:card];
                [values addObject:valueLabel];
                [titleLabelArr addObject:titleLabel];
            }
        }

        _valueLabels = [values copy];
        _titleLabels = [titleLabelArr copy];
        _cardViews = [cards copy];

        [NSLayoutConstraint activateConstraints:@[
            [verticalStack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:kStatsCardSpacing],
            [verticalStack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [verticalStack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [verticalStack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-kStatsCardSpacing],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    for (UILabel *label in self.valueLabels) {
        label.text = @"-";
    }
}

/// 安全取数字并格式化为字符串
- (NSString *)stringFromNumber:(id)number {
    if (!number || number == [NSNull null]) return @"-";
    if ([number isKindOfClass:[NSNumber class]]) {
        long long ll = [number longLongValue];
        return [NSString stringWithFormat:@"%lld", ll];
    }
    if ([number isKindOfClass:[NSString class]]) {
        return (NSString *)number;
    }
    return @"-";
}

- (void)configureWithData:(NSDictionary *)overview {
    if (![overview isKindOfClass:[NSDictionary class]]) {
        [self prepareForReuse];
        return;
    }
    // 6 个值顺序对应：在线用户数 / 总用户数 / MC启动总次数 / 崩溃总次数 / 游戏总时长 / 启动器开启次数
    // 字段名与 stats.php 返回的 JSON 一致
    NSArray *keys = @[@"online_users", @"total_users", @"total_mc_launches",
                      @"total_crashes", @"total_play_time_hours", @"launcher_opens"];
    for (NSInteger i = 0; i < 6; i++) {
        NSString *key = keys[i];
        id value = overview[key];
        if (!value || value == [NSNull null]) {
            self.valueLabels[i].text = @"-";
            continue;
        }
        if (i == 4) {
            // 游戏总时长：格式化为 Xh Ym
            double hours = 0.0;
            if ([value isKindOfClass:[NSNumber class]]) {
                hours = [value doubleValue];
            } else if ([value isKindOfClass:[NSString class]]) {
                hours = [(NSString *)value doubleValue];
            }
            self.valueLabels[i].text = [self formatPlaytimeHours:hours];
        } else {
            self.valueLabels[i].text = [self stringFromNumber:value];
        }
    }
}

/// 将小时数格式化为 "Xh Ym"
- (NSString *)formatPlaytimeHours:(double)hours {
    if (hours <= 0) return @"0h 0m";
    NSInteger totalMinutes = (NSInteger)(hours * 60.0);
    NSInteger h = totalMinutes / 60;
    NSInteger m = totalMinutes % 60;
    return [NSString stringWithFormat:@"%ldh %ldm", (long)h, (long)m];
}

@end

#pragma mark - StatsDistributionCell

/// 通用分布 Cell：左侧标题（可选副标题），右侧数量与占比
@interface StatsDistributionCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UILabel *percentLabel;
- (void)configureWithTitle:(NSString *)title
                  subtitle:(nullable NSString *)subtitle
                     count:(NSInteger)count
                 percent:(CGFloat)percent
               showPercent:(BOOL)showPercent;
@end

@implementation StatsDistributionCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        _titleLabel.textColor = [UIColor labelColor];
        _titleLabel.numberOfLines = 1;
        [self.contentView addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = [UIFont systemFontOfSize:12];
        _subtitleLabel.textColor = [UIColor secondaryLabelColor];
        _subtitleLabel.numberOfLines = 1;
        [self.contentView addSubview:_subtitleLabel];

        _countLabel = [[UILabel alloc] init];
        _countLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _countLabel.font = [UIFont boldSystemFontOfSize:16];
        _countLabel.textColor = [UIColor labelColor];
        _countLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:_countLabel];

        _percentLabel = [[UILabel alloc] init];
        _percentLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _percentLabel.font = [UIFont systemFontOfSize:12];
        _percentLabel.textColor = [UIColor secondaryLabelColor];
        _percentLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:_percentLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.centerXAnchor],

            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],
            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.centerXAnchor],
            [_subtitleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12],

            [_countLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],
            [_countLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],

            [_percentLabel.topAnchor constraintEqualToAnchor:_countLabel.bottomAnchor constant:2],
            [_percentLabel.trailingAnchor constraintEqualToAnchor:_countLabel.trailingAnchor],
            [_percentLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-12],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.titleLabel.text = nil;
    self.subtitleLabel.text = nil;
    self.countLabel.text = nil;
    self.percentLabel.text = nil;
    self.percentLabel.hidden = YES;
}

- (void)configureWithTitle:(NSString *)title
                  subtitle:(nullable NSString *)subtitle
                     count:(NSInteger)count
                 percent:(CGFloat)percent
               showPercent:(BOOL)showPercent {
    self.titleLabel.text = title ?: @"";
    self.subtitleLabel.text = subtitle;
    self.subtitleLabel.hidden = subtitle.length == 0;
    self.countLabel.text = [NSString stringWithFormat:@"%ld", (long)count];
    if (showPercent) {
        self.percentLabel.text = [NSString stringWithFormat:@"%.1f%%", percent];
        self.percentLabel.hidden = NO;
    } else {
        self.percentLabel.hidden = YES;
    }
}

@end

#pragma mark - StatsMCVersionCell

/// Minecraft 版本统计 Cell：版本号 / 启动次数 / 游戏时长 / 崩溃次数
@interface StatsMCVersionCell : UITableViewCell
@property (nonatomic, strong) UILabel *versionLabel;
@property (nonatomic, strong) UILabel *launchesLabel;
@property (nonatomic, strong) UILabel *playtimeLabel;
@property (nonatomic, strong) UILabel *crashesLabel;
@end

@implementation StatsMCVersionCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];

        _versionLabel = [[UILabel alloc] init];
        _versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _versionLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _versionLabel.textColor = [UIColor labelColor];
        [self.contentView addSubview:_versionLabel];

        // 三个统计小标签横向排列（启动次数 / 游戏时长 / 崩溃次数）
        UIStackView *statsStack = [[UIStackView alloc] init];
        statsStack.translatesAutoresizingMaskIntoConstraints = NO;
        statsStack.axis = UILayoutConstraintAxisHorizontal;
        statsStack.distribution = UIStackViewDistributionFillEqually;
        statsStack.spacing = 8;
        [self.contentView addSubview:statsStack];

        _launchesLabel = [self makeStatLabel];
        _playtimeLabel = [self makeStatLabel];
        _crashesLabel = [self makeStatLabel];
        [statsStack addArrangedSubview:_launchesLabel];
        [statsStack addArrangedSubview:_playtimeLabel];
        [statsStack addArrangedSubview:_crashesLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_versionLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],
            [_versionLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_versionLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],

            [statsStack.topAnchor constraintEqualToAnchor:_versionLabel.bottomAnchor constant:6],
            [statsStack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [statsStack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [statsStack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12],
        ]];
    }
    return self;
}

/// 构造统计小标签：居中、圆角背景、12 号字
- (UILabel *)makeStatLabel {
    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont systemFontOfSize:12];
    label.textColor = [UIColor secondaryLabelColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.backgroundColor = [UIColor secondarySystemBackgroundColor];
    label.layer.cornerRadius = 8;
    label.layer.cornerCurve = kCACornerCurveContinuous;
    label.layer.masksToBounds = YES;
    // 通过 height 约束撑开圆角背景
    [label.heightAnchor constraintEqualToConstant:28].active = YES;
    return label;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _versionLabel.text = nil;
    _launchesLabel.text = nil;
    _playtimeLabel.text = nil;
    _crashesLabel.text = nil;
}

- (void)configureWithVersion:(NSString *)version
                    launches:(NSInteger)launches
                   playtimeHours:(double)playtimeHours
                     crashes:(NSInteger)crashes {
    _versionLabel.text = [NSString stringWithFormat:@"Minecraft %@", version ?: @""];
    _launchesLabel.text = [NSString stringWithFormat:@"启动 %ld 次", (long)launches];
    _playtimeLabel.text = [NSString stringWithFormat:@"%@", [self formatPlaytimeHours:playtimeHours]];
    _crashesLabel.text = [NSString stringWithFormat:@"崩溃 %ld 次", (long)crashes];
}

/// 将小时数格式化为 "Xh Ym"
- (NSString *)formatPlaytimeHours:(double)hours {
    if (hours <= 0) return @"0h 0m";
    NSInteger totalMinutes = (NSInteger)(hours * 60.0);
    NSInteger h = totalMinutes / 60;
    NSInteger m = totalMinutes % 60;
    return [NSString stringWithFormat:@"%ldh %ldm", (long)h, (long)m];
}

@end

#pragma mark - AnalyticsStatsViewController

@interface AnalyticsStatsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UIButton *retryButton;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) NSDictionary *statsData;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, copy) NSString *lastErrorMessage;
@end

@implementation AnalyticsStatsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"使用统计";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    // 适配自定义启动器背景
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    [self setupNavBar];
    [self setupUI];

    // 透明化 tableView 背景，避免遮挡全局背景
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.backgroundView = nil;

    // 监听背景效果变化通知
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reapplyBackgroundEffect)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];

    [self loadStats];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reapplyBackgroundEffect {
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.backgroundView = nil;
    [self.tableView reloadData];
}

#pragma mark - Setup

- (void)setupNavBar {
    // 左上角关闭按钮（参考 AnnouncementListViewController）
    UIBarButtonItem *closeItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                                                target:self
                                                                                action:@selector(closeAction)];
    self.navigationItem.leftBarButtonItem = closeItem;

    // 右上角刷新按钮
    UIBarButtonItem *refreshItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                  target:self
                                                                                  action:@selector(forceRefreshAction)];
    self.navigationItem.rightBarButtonItem = refreshItem;
}

- (void)setupUI {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 16, 0, 16);
    self.tableView.estimatedRowHeight = 60;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.alwaysBounceVertical = YES;
    [self.tableView registerClass:[StatsOverviewCell class] forCellReuseIdentifier:@"StatsOverviewCell"];
    [self.tableView registerClass:[StatsDistributionCell class] forCellReuseIdentifier:@"StatsDistributionCell"];
    [self.tableView registerClass:[StatsMCVersionCell class] forCellReuseIdentifier:@"StatsMCVersionCell"];
    [self.view addSubview:self.tableView];

    // 下拉刷新
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(forceRefreshAction) forControlEvents:UIControlEventValueChanged];
    [self.tableView addSubview:self.refreshControl];

    // 加载指示器
    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.activityIndicator.hidesWhenStopped = YES;
    [self.view addSubview:self.activityIndicator];

    // 错误提示标签
    self.errorLabel = [[UILabel alloc] init];
    self.errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.errorLabel.textColor = [UIColor secondaryLabelColor];
    self.errorLabel.textAlignment = NSTextAlignmentCenter;
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.hidden = YES;
    [self.view addSubview:self.errorLabel];

    // 重试按钮
    self.retryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.retryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.retryButton setTitle:@"重试" forState:UIControlStateNormal];
    self.retryButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [self.retryButton addTarget:self action:@selector(loadStats) forControlEvents:UIControlEventTouchUpInside];
    self.retryButton.hidden = YES;
    [self.view addSubview:self.retryButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.activityIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.activityIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

        [self.errorLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.errorLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-20],
        [self.errorLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:32],
        [self.errorLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-32],

        [self.retryButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.retryButton.topAnchor constraintEqualToAnchor:self.errorLabel.bottomAnchor constant:12],
    ]];
}

#pragma mark - URL 构造

/// 从 general.news_url 派生 stats.php 的 URL
- (NSString *)statsAPIURLString {
    NSString *url = getPrefObject(@"general.news_url");
    if (url.length == 0) {
        url = @"https://newamethyst.ct.ws/api/announcements.json";
    }
    // 将 /api/announcements.json 替换为 /api/stats.php
    if ([url containsString:@"/api/announcements.json"]) {
        return [url stringByReplacingOccurrencesOfString:@"/api/announcements.json"
                                              withString:@"/api/stats.php"];
    }
    // 兜底：若 news_url 已被改成其他形态，则尝试替换最后一段路径为 stats.php
    NSURL *parsed = [NSURL URLWithString:url];
    if (parsed) {
        NSURLComponents *comp = [NSURLComponents componentsWithURL:parsed resolvingAgainstBaseURL:NO];
        if (comp && comp.path.length > 0) {
            NSMutableArray *segments = [[comp.path pathComponents] mutableCopy];
            if (segments.count > 0) {
                // 替换最后一段为 stats.php（pathComponents 首元素为 "/"，用 pathWithComponents 重建）
                [segments replaceObjectAtIndex:segments.count - 1 withObject:@"stats.php"];
                comp.path = [NSString pathWithComponents:segments];
                return comp.string;
            }
        }
    }
    return @"https://newamethyst.ct.ws/api/stats.php";
}

#pragma mark - Data Loading

- (void)loadStats {
    if (self.isLoading) return;
    self.isLoading = YES;
    self.errorLabel.hidden = YES;
    self.retryButton.hidden = YES;

    // 首次加载时显示中央指示器
    if (!self.statsData || self.statsData.count == 0) {
        [self.activityIndicator startAnimating];
    }

    NSString *urlString = [self statsAPIURLString];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        [self handleError:[NSError errorWithDomain:@"AnalyticsStats" code:1
                                       userInfo:@{NSLocalizedDescriptionKey: @"无效的统计 URL"}]];
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];
    [request setValue:@"Air/1.0 (iOS)" forHTTPHeaderField:@"User-Agent"];
    request.timeoutInterval = 15.0;

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.isLoading = NO;
        [strongSelf.activityIndicator stopAnimating];
        [strongSelf.refreshControl endRefreshing];

        if (error || !data || ((NSHTTPURLResponse *)response).statusCode != 200) {
            NSString *msg = error.localizedDescription;
            if (msg.length == 0) {
                NSInteger code = ((NSHTTPURLResponse *)response).statusCode;
                msg = [NSString stringWithFormat:@"服务器返回错误（HTTP %ld）", (long)code];
            }
            [strongSelf handleError:[NSError errorWithDomain:@"AnalyticsStats" code:2
                                                   userInfo:@{NSLocalizedDescriptionKey: msg ?: @"加载失败"}]];
            return;
        }

        NSError *parseError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        if (parseError || ![json isKindOfClass:[NSDictionary class]]) {
            [strongSelf handleError:[NSError errorWithDomain:@"AnalyticsStats" code:3
                                                   userInfo:@{NSLocalizedDescriptionKey: @"统计数据 JSON 解析失败"}]];
            return;
        }

        strongSelf.statsData = json;
        strongSelf.errorLabel.hidden = YES;
        strongSelf.retryButton.hidden = YES;
        [strongSelf.tableView reloadData];
    }];
    [task resume];
}

- (void)forceRefreshAction {
    [self loadStats];
}

- (void)handleError:(NSError *)error {
    self.lastErrorMessage = error.localizedDescription ?: @"加载失败";
    // 仅在完全没有数据时显示全屏错误提示
    if (!self.statsData || self.statsData.count == 0) {
        self.errorLabel.text = [NSString stringWithFormat:@"加载失败\n%@", self.lastErrorMessage];
        self.errorLabel.hidden = NO;
        self.retryButton.hidden = NO;
    } else {
        // 已有数据时仅弹窗提示，不破坏现有展示
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"刷新失败"
                                                                       message:self.lastErrorMessage
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)closeAction {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 数据取值辅助

/// 安全取数组（防御非数组类型）
- (NSArray *)arrayForKey:(NSString *)key {
    id obj = self.statsData[key];
    if ([obj isKindOfClass:[NSArray class]]) return obj;
    return @[];
}

/// 安全取字典中的数字（兼容 NSNumber / NSString）
- (NSInteger)integerValueIn:(NSDictionary *)dict forKey:(NSString *)key {
    id v = dict[key];
    if (!v || v == [NSNull null]) return 0;
    if ([v isKindOfClass:[NSNumber class]]) return [v integerValue];
    if ([v isKindOfClass:[NSString class]]) return [(NSString *)v integerValue];
    return 0;
}

/// 安全取字典中的 double（兼容 NSNumber / NSString）
- (double)doubleValueIn:(NSDictionary *)dict forKey:(NSString *)key {
    id v = dict[key];
    if (!v || v == [NSNull null]) return 0.0;
    if ([v isKindOfClass:[NSNumber class]]) return [v doubleValue];
    if ([v isKindOfClass:[NSString class]]) return [(NSString *)v doubleValue];
    return 0.0;
}

/// 安全取字符串
- (NSString *)stringValueIn:(NSDictionary *)dict forKey:(NSString *)key {
    id v = dict[key];
    if (!v || v == [NSNull null]) return @"";
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v stringValue];
    return @"";
}

/// 越狱状态英文转中文
- (NSString *)jailbreakStatusToChinese:(NSString *)status {
    if (status.length == 0) return @"未知";
    NSString *lower = [status lowercaseString];
    if ([lower containsString:@"jail"] || [lower containsString:@"jb"]) return @"已越狱";
    if ([lower containsString:@"non"] || [lower containsString:@"normal"] || [lower containsString:@"stock"]) return @"未越狱";
    if ([lower containsString:@"troll"]) return @"TrollStore";
    if ([lower containsString:@"unknown"]) return @"未知";
    return status;
}

/// 计算某分布数组的总数（用于百分比计算）
- (NSInteger)totalOfArray:(NSArray *)array countKey:(NSString *)countKey {
    NSInteger total = 0;
    for (NSDictionary *dict in array) {
        if ([dict isKindOfClass:[NSDictionary class]]) {
            total += [self integerValueIn:dict forKey:countKey];
        }
    }
    return total;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return StatsSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (!self.statsData) return 0;

    switch (section) {
        case StatsSectionOverview:
            return 1;
        case StatsSectionDeviceModels:
            return [self arrayForKey:@"device_models"].count;
        case StatsSectionIosVersions:
            return [self arrayForKey:@"ios_versions"].count;
        case StatsSectionLauncherVersions:
            return [self arrayForKey:@"launcher_versions"].count;
        case StatsSectionJailbreakStatus:
            return [self arrayForKey:@"jailbreak_distribution"].count;
        case StatsSectionMcVersions:
            return [self arrayForKey:@"mc_version_stats"].count;
        case StatsSectionRecentCrashes:
            return [self arrayForKey:@"recent_crashes"].count;
        case StatsSectionOther:
            return 1;
        default:
            return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // 适配自定义启动器背景：为 cell 注入毛玻璃/半透明效果
    switch (indexPath.section) {
        case StatsSectionOverview: {
            StatsOverviewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"StatsOverviewCell" forIndexPath:indexPath];
            // 概览数据直接从 statsData 顶层读取（stats.php 返回的 JSON 是扁平结构）
            [cell configureWithData:self.statsData];
            [[BackgroundManager sharedManager] applyEffectToCell:cell];
            return cell;
        }
        case StatsSectionDeviceModels:
        case StatsSectionIosVersions:
        case StatsSectionLauncherVersions:
        case StatsSectionJailbreakStatus:
        case StatsSectionRecentCrashes:
        case StatsSectionOther: {
            StatsDistributionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"StatsDistributionCell" forIndexPath:indexPath];
            [self configureDistributionCell:cell forIndexPath:indexPath];
            [[BackgroundManager sharedManager] applyEffectToCell:cell];
            return cell;
        }
        case StatsSectionMcVersions: {
            StatsMCVersionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"StatsMCVersionCell" forIndexPath:indexPath];
            NSArray *array = [self arrayForKey:@"mc_version_stats"];
            if (indexPath.row < (NSInteger)array.count) {
                NSDictionary *dict = array[indexPath.row];
                [cell configureWithVersion:[self stringValueIn:dict forKey:@"version"]
                                  launches:[self integerValueIn:dict forKey:@"launch_count"]
                             playtimeHours:[self doubleValueIn:dict forKey:@"play_time_hours"]
                                   crashes:[self integerValueIn:dict forKey:@"crash_count"]];
            }
            [[BackgroundManager sharedManager] applyEffectToCell:cell];
            return cell;
        }
        default:
            return [UITableViewCell new];
    }
}

/// 配置通用分布 Cell（设备型号 / 系统版本 / 启动器版本 / 越狱状态 / 近期崩溃 / 其他）
- (void)configureDistributionCell:(StatsDistributionCell *)cell forIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case StatsSectionDeviceModels: {
            NSArray *array = [self arrayForKey:@"device_models"];
            NSInteger total = [self totalOfArray:array countKey:@"count"];
            NSDictionary *dict = array[indexPath.row];
            // stats.php 返回 label 字段（人类可读名称），fallback 到 model
            NSString *name = [self stringValueIn:dict forKey:@"label"];
            if (name.length == 0) name = [self stringValueIn:dict forKey:@"model"];
            NSInteger count = [self integerValueIn:dict forKey:@"count"];
            CGFloat percent = total > 0 ? (CGFloat)count / total * 100.0 : 0.0;
            [cell configureWithTitle:name subtitle:nil count:count percent:percent showPercent:YES];
            break;
        }
        case StatsSectionIosVersions: {
            NSArray *array = [self arrayForKey:@"ios_versions"];
            NSInteger total = [self totalOfArray:array countKey:@"count"];
            NSDictionary *dict = array[indexPath.row];
            NSString *version = [self stringValueIn:dict forKey:@"version"];
            if (version.length == 0) version = [self stringValueIn:dict forKey:@"ios_version"];
            NSInteger count = [self integerValueIn:dict forKey:@"count"];
            CGFloat percent = total > 0 ? (CGFloat)count / total * 100.0 : 0.0;
            [cell configureWithTitle:[NSString stringWithFormat:@"iOS %@", version]
                            subtitle:nil
                               count:count
                            percent:percent
                        showPercent:YES];
            break;
        }
        case StatsSectionLauncherVersions: {
            NSArray *array = [self arrayForKey:@"launcher_versions"];
            NSInteger total = [self totalOfArray:array countKey:@"count"];
            NSDictionary *dict = array[indexPath.row];
            NSString *version = [self stringValueIn:dict forKey:@"version"];
            if (version.length == 0) version = [self stringValueIn:dict forKey:@"launcher_version"];
            NSInteger count = [self integerValueIn:dict forKey:@"count"];
            CGFloat percent = total > 0 ? (CGFloat)count / total * 100.0 : 0.0;
            [cell configureWithTitle:[NSString stringWithFormat:@"v%@", version]
                            subtitle:nil
                               count:count
                            percent:percent
                        showPercent:YES];
            break;
        }
        case StatsSectionJailbreakStatus: {
            NSArray *array = [self arrayForKey:@"jailbreak_distribution"];
            NSInteger total = [self totalOfArray:array countKey:@"count"];
            NSDictionary *dict = array[indexPath.row];
            NSString *status = [self stringValueIn:dict forKey:@"status"];
            NSString *cnStatus = [self jailbreakStatusToChinese:status];
            NSInteger count = [self integerValueIn:dict forKey:@"count"];
            CGFloat percent = total > 0 ? (CGFloat)count / total * 100.0 : 0.0;
            [cell configureWithTitle:cnStatus subtitle:nil count:count percent:percent showPercent:YES];
            break;
        }
        case StatsSectionRecentCrashes: {
            NSArray *array = [self arrayForKey:@"recent_crashes"];
            NSDictionary *dict = array[indexPath.row];
            // stats.php 返回 crash_type 字段
            NSString *type = [self stringValueIn:dict forKey:@"crash_type"];
            NSString *mcVersion = [self stringValueIn:dict forKey:@"mc_version"];
            NSString *device = [self stringValueIn:dict forKey:@"device_model"];
            NSInteger count = [self integerValueIn:dict forKey:@"count"];
            NSString *subtitle = [NSString stringWithFormat:@"%@ · %@", mcVersion, device];
            [cell configureWithTitle:type subtitle:subtitle count:count percent:0 showPercent:NO];
            break;
        }
        case StatsSectionOther: {
            id installs = self.statsData[@"original_amethyst_installed"];
            NSInteger count = 0;
            if ([installs isKindOfClass:[NSNumber class]]) {
                count = [installs integerValue];
            } else if ([installs isKindOfClass:[NSString class]]) {
                count = [(NSString *)installs integerValue];
            }
            [cell configureWithTitle:@"原版 Amethyst 安装数"
                            subtitle:nil
                               count:count
                            percent:0
                        showPercent:NO];
            break;
        }
        default:
            break;
    }
}

#pragma mark - Section Header

- (NSString *)titleForSection:(NSInteger)section {
    switch (section) {
        case StatsSectionOverview:           return @"概览";
        case StatsSectionDeviceModels:       return @"设备型号分布";
        case StatsSectionIosVersions:        return @"系统版本分布";
        case StatsSectionLauncherVersions:   return @"启动器版本分布";
        case StatsSectionJailbreakStatus:    return @"签名/越狱状态";
        case StatsSectionMcVersions:         return @"Minecraft 版本统计";
        case StatsSectionRecentCrashes:      return @"近期崩溃统计（7天内）";
        case StatsSectionOther:              return @"其他统计";
        default:                             return @"";
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return kStatsHeaderHeight;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, kStatsHeaderHeight)];
    header.backgroundColor = [UIColor clearColor];

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = [self titleForSection:section];
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    label.textColor = [UIColor secondaryLabelColor];
    [header addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [label.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [label.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
    ]];

    return header;
}

#pragma mark - 空数据展示

/// 在最后一个分区尾部或全空时，显示"暂无数据"提示（通过 footer 实现）
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    NSInteger rows = [self tableView:tableView numberOfRowsInSection:section];
    if (rows == 0 && self.statsData) {
        return 44;
    }
    return CGFLOAT_MIN;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    NSInteger rows = [self tableView:tableView numberOfRowsInSection:section];
    if (rows == 0 && self.statsData) {
        UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 44)];
        UILabel *label = [[UILabel alloc] init];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.text = @"暂无数据";
        label.font = [UIFont systemFontOfSize:13];
        label.textColor = [UIColor tertiaryLabelColor];
        label.textAlignment = NSTextAlignmentCenter;
        [footer addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.centerXAnchor constraintEqualToAnchor:footer.centerXAnchor],
            [label.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor],
        ]];
        return footer;
    }
    return nil;
}

@end
