//
//  UserBehaviorMonitorManager.m
//  测试代码创建
//
//  Created by 刘志伟 on 2017/7/26.
//  Copyright © 2017年 micheal. All rights reserved.
//

#if (defined DEBUG) || (TARGET_IPHONE_SIMULATOR) //如果当前为debug模式且用模拟器运行则输出NSLog
#define NSLog(format, ...) NSLog(format, ## __VA_ARGS__)
#else  //其他情况都不输出
#define NSLog(...) {}
#endif

#import "MCUserBehaviorMonitorManager.h"
#import <objc/runtime.h>
#import "Aspects.h"
#import <UIKit/UIKit.h>
#import "MCReachability.h"
#import "StatisticDBManager.h"

static NSString *firstStart = @"AppFirstStart";
static NSString *DBLogID = @"MCUserBehaviorMonitorManager";
static MCUserBehaviorMonitorManager *selfClass = nil;

@interface MCUserBehaviorMonitorManager (){
    StatisticDBManager *DBManager;
}

/*
 判断是否为tabBar切换index
 */
@property (nonatomic, assign) BOOL isTabBarSelect;

/*
 收集的统计日志 格式： 名称/ 操作时间/ 持续时间/ 用户/ ID/ ...
 */
@property (nonatomic, strong) NSMutableArray *collectionLog;

/*
 普通页面控制器信息存储数组
 */
@property (nonatomic, strong) NSMutableArray *normalVCUse;

/*
 当前tabBar显示的子控制器信息
 */
@property (nonatomic, strong) NSMutableDictionary       *currentSubVCInfo;


@property (nonatomic, strong) NSTimer        *timer;        // 发送日志计时间周期
@property (nonatomic, strong) NSDate         *startDate;    // 程序启动时刻
@property (nonatomic, strong) NSDate         *aliveDate;    // 程序进入前台时刻
@property (nonatomic, strong) NSDate         *backDate;     // 程序进入后台时刻
@property (nonatomic, assign) NSTimeInterval durationBack;  // 程序在后台的时长

@end

@implementation MCUserBehaviorMonitorManager

+ (instancetype)shareManager{
    static MCUserBehaviorMonitorManager *manager;
    static dispatch_once_t Token;
    dispatch_once (&Token,^{
        manager = [[MCUserBehaviorMonitorManager alloc] init];
        [manager initSettings];
        selfClass = manager;
    });
    
    return manager;
}

#pragma mark 初始化设置
- (void)initSettings{
    [self addAppStatusNoticefication];
    self.isTabBarSelect = NO;
    self.enableExceptionLog = YES;
    self.logStrategy = MCLogSendStrategyAppLaunch;
    self.logSendInterval = 1;
    self.sessionResumeInterval = 30;
}

#pragma mark 配置文件读取
- (void)setupWithConfiguration:(NSDictionary *)configuration{
    // 普通页面统计
    [self pagesUsingStatisticWithArray:configuration[@"trackedPages"]];
    
    // tabBar控制器切换统计
    [self tabBarControllerSwitchPagesDelegateWithDict:configuration[@"trackedTabBarEvents"]];
    [self tabBarSubVCSwitchWithArray:configuration[@"trackedTabBarSubVCEvent"]];
    
    //功能使用统计
    [self functionsUsingStatisticWithArray:configuration[@"trackedEvents"]];
}

#pragma mark @--默认属性设置
/*
 是否开启奔溃日志属性
 */
- (void)setEnableExceptionLog:(BOOL)enableExceptionLog{
    _enableExceptionLog = enableExceptionLog;
    if (_enableExceptionLog) {
        NSSetUncaughtExceptionHandler (&UncaughtExceptionHandler);
    }
}

/*
 发送策略
 */
- (void)setLogStrategy:(MCLogSendStrategy)logStrategy{
    _logStrategy = logStrategy;
    
    if (_logStrategy == MCLogSendStrategyCustom) {
        self.timer = [NSTimer scheduledTimerWithTimeInterval:self.logSendInterval*60*60 target:self selector:@selector(sendLogsToServer) userInfo:nil repeats:YES];
        [self.timer fire];
    }
}

#pragma mark @--发送日志给后台
- (void)sendLogsToServer{
    if (self.logSendWifiOnly) {
        
        if ([[MCReachability reachabilityForInternetConnection] currentReachabilityStatus] == MCReachableViaWiFi) {
            NSLog(@"发送日志给后台");
        }
    }
    else {
        NSLog(@"发送日志给后台");
    }
}

#pragma mark 统一格式综合统计
- (void)markStatisticLogWithLogName:(NSString *)logName Duration:(double)duration{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"YYYY-MM-dd HH:mm:ss";
    NSString *dateString = [dateFormatter stringFromDate:[NSDate date]];
    NSString *durationStr = [NSString stringWithFormat:@"%f",duration];
    
    NSDictionary *dic = @{@"StatisticName":logName,
                          @"StatisticDate":dateString,
                          @"StatisticDuration":durationStr,
                          @"StatisticUserId":@"liuzhiwei",
                          @"StatisticID":DBLogID};
    
    DBManager = [StatisticDBManager openListData];
    BOOL addData = [DBManager addData:dic];
    if (addData) {
        NSLog(@"数据插入成功");
    }
    else {
        NSLog(@"数据插入失败");
    }
}

#pragma mark 监听程序状态用于统计
- (void)addAppStatusNoticefication{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onAppUIApplicationDidFinishLaunchingNotification:)
                                                 name:UIApplicationDidFinishLaunchingNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onAppWillTerminate:)
                                                 name:UIApplicationWillTerminateNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onAppDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onAppDidEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification object:nil];
}

#pragma mark 普通页面使用统计
- (void)pagesUsingStatisticWithArray:(NSArray *)array{
    __block __weak typeof(self) weakSelf = self;
    // screen views tracking
    for (NSDictionary *trackedScreen in array) {
        Class clazz = NSClassFromString(trackedScreen[@"className"]);
        
        [clazz aspect_hookSelector:@selector(viewDidLoad)
                       withOptions:AspectPositionAfter
                        usingBlock:^(id<AspectInfo> aspectInfo) {
                            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                                           ^{
                                               
                                               NSLog(@"className:--- %@ --- 打开",clazz);
                                               NSDictionary *classInfo = @{@"className":trackedScreen[@"className"],
                                                                           @"pageName":trackedScreen[@"pageName"],
                                                                           @"classUseDate":[NSDate date]};
                                               [weakSelf.normalVCUse addObject:classInfo];
                                           });
                        }
                             error:nil];
        
        SEL selektor = NSSelectorFromString(@"dealloc");
        [clazz aspect_hookSelector:selektor
                       withOptions:AspectPositionBefore
                        usingBlock:^(id<AspectInfo> aspectInfo) {
                            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                                           ^{
                                               
                                               for (NSDictionary *classInfo in weakSelf.normalVCUse) {
                                                   if ([classInfo[@"className"] isEqualToString:trackedScreen[@"className"]]) {
                                                       //                                                       NSLog(@"className:--- %@ --- 关闭",clazz);
                                                       
                                                       NSDate *date = classInfo[@"classUseDate"];
                                                       [weakSelf.normalVCUse removeObject:classInfo];
                                                       if (date ) {
                                                           NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:date];
                                                           /*
                                                            当使用过程中程序进入后台并停留一段时间时，统计时长需要减去该段时间
                                                            */
                                                           if (self.backDate && ([self.backDate timeIntervalSinceDate:date] > 0)) {
                                                               duration = duration - [self.aliveDate timeIntervalSinceDate:self.backDate];
                                                           }
                                                           NSLog(@"className:--- %@ --- 用户使用并停留  useTimeDuration: %.2f秒",clazz,duration);
                                                           [weakSelf markStatisticLogWithLogName:trackedScreen[@"pageName"] Duration:duration];
                                                       }
                                                       
                                                   }
                                               }
                                               
                                           });
                        }
                             error:nil];
    }
}

#pragma mark 功能使用统计
- (void)functionsUsingStatisticWithArray:(NSArray *)array{
    
    for (NSDictionary *trackedEvents in array) {
        Class clazz = NSClassFromString(trackedEvents[@"className"]);
        SEL selektor = NSSelectorFromString(trackedEvents[@"selector"]);
        __weak typeof(self) weakSelf = self;
        [clazz  aspect_hookSelector:selektor
                        withOptions:AspectPositionBefore
                         usingBlock:^(id<AspectInfo> aspectInfo) {
                             dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                                            ^{
                                                NSLog(@"className:--- %@ ---  \n ",clazz);
                                                [weakSelf markStatisticLogWithLogName:trackedEvents[@"eventName"] Duration:0.0];
                                            });
                         }
                              error:nil];
        
    }
}

#pragma mark 统计崩溃
// 崩溃时的回调函数
void UncaughtExceptionHandler(NSException * exception) {
    NSArray * arr = [exception callStackSymbols];
    NSString * reason = [exception reason]; // // 崩溃的原因  可以有崩溃的原因(数组越界,字典nil,调用未知方法...) 崩溃的控制器以及方法
    NSString * name = [exception name];
    
    NSString *crashLogInfo = [NSString stringWithFormat:@"exception type : %@ \n crash reason : %@ \n call stack", name, reason];
    NSLog(@"异常错误报告：%@",crashLogInfo);
    
    [selfClass markStatisticLogWithLogName:crashLogInfo Duration:0.0];
    NSString *urlStr = [NSString stringWithFormat:@"mailto://misterzhiwei@outlook.com?subject=bug报告&body=感谢您的配合!" "错误详情:%@",crashLogInfo];
    //    NSURL *url = [NSURL URLWithString:[urlStr stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    //    [[UIApplication sharedApplication] openURL:url];
}

#pragma mark UITabBarControllerDelegate代理方法实现监听
- (void)tabBarControllerSwitchPagesDelegateWithDict:(NSDictionary *)dict{
    Class clazz = NSClassFromString(dict[@"className"]);
    SEL selektor = NSSelectorFromString(@"tabBarController:didSelectViewController:");
    __block __weak typeof(self) weakSelf = self;
    [clazz  aspect_hookSelector:selektor
                    withOptions:AspectPositionAfter
                     usingBlock:^(id<AspectInfo> aspectInfo) {
                         dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                                        ^{
                                            NSLog(@"className:--- %@ ---  ",clazz);
                                            weakSelf.isTabBarSelect = YES;
                                        });
                     }
                          error:nil];
}

#pragma mark tabBar控制器子页面使用统计
- (void)tabBarSubVCSwitchWithArray:(NSArray *)array{
    
    for (int i = 0; i < array.count; i++) {
        NSDictionary *trackedScreen = array[i];
        Class clazz = NSClassFromString(trackedScreen[@"className"]);
        if (i == 0) {
            
            NSLog(@"className:--- %@ --- 打开 \n  ",trackedScreen[@"className"]);
            self.currentSubVCInfo = [NSMutableDictionary dictionaryWithDictionary:@{@"className":trackedScreen[@"className"],
                                                                                    @"pageName":trackedScreen[@"pageName"],
                                                                                    @"classUseDate":[NSDate date]}];
        }
        __block __weak typeof(self) weakSelf = self;
        [clazz  aspect_hookSelector:@selector(viewDidAppear:)
                        withOptions:AspectPositionAfter
                         usingBlock:^(id<AspectInfo> aspectInfo) {
                             dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                                            ^{
                                                
                                                if (weakSelf.isTabBarSelect) {
                                                    // tabBarController关闭的上一个选中subVC
                                                    NSLog(@"className: --- %@ --- 关闭 \n ",weakSelf.currentSubVCInfo[@"className"]);
                                                    
                                                    NSDate *date = weakSelf.currentSubVCInfo[@"classUseDate"];
                                                    if (date) {
                                                        NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:date];
                                                        NSLog(@"className: --- %@ --- 用户使用并停留 duration:%.2f \n ",weakSelf.currentSubVCInfo[@"className"], duration);
                                                        /*
                                                         当使用过程中程序进入后台并停留一段时间时，统计时长需要减去该段时间
                                                         */
                                                        if (self.backDate && ([self.backDate timeIntervalSinceDate:self.currentSubVCInfo[@"classUseDate"]] > 0)) {
                                                            duration = duration - [self.aliveDate timeIntervalSinceDate:self.backDate];
                                                        }
                                                        [weakSelf markStatisticLogWithLogName:weakSelf.currentSubVCInfo[@"pageName"] Duration:duration];
                                                    }
                                                    
                                                    // tabBarController打开的下一个选中subVC
                                                    weakSelf.isTabBarSelect = NO;
                                                    
                                                    weakSelf.currentSubVCInfo = [NSMutableDictionary dictionaryWithDictionary:@{@"className":trackedScreen[@"className"],
                                                                                                                                @"pageName":trackedScreen[@"pageName"],
                                                                                                                                @"classUseDate":[NSDate date]}];
                                                    NSLog(@"className:--- %@ --- 打开 \n  ",weakSelf.currentSubVCInfo[@"className"]);
                                                }
                                            });
                         }
                              error:nil];
        
        
    }
    
}

#pragma mark UIApplicationDelegate impl
/*
 程序开启
 */
- (void)onAppUIApplicationDidFinishLaunchingNotification:(NSNotification *)noticefication{
    NSLog(@"用户统计 -- 程序开启");
    UIDevice *device = [[UIDevice alloc] init];
    NSString *name = device.name;       //获取设备所有者的名称
    NSString *type = device.localizedModel; //获取设备的类别
    NSString *systemName = device.systemName;   //获取当前运行的系统
    NSString *systemVersion = device.systemVersion;//获取当前系统的版本
    NSLog(@"\n 设备所有者名称：%@--\n 设备类别：%@-- \n 当前运行的系统：%@--\n 当前系统的版本：%@--\n",name,type,systemName,systemVersion);
    if (!self.startDate) {
        self.startDate = [NSDate date];
    }
    
    if (self.logStrategy == MCLogSendStrategyAppLaunch) { // 程序每次启动时发送日志
        NSLog(@"程序每次启动时发送日志");
        // 发送日志
        [self sendLogsToServer];
    }
    else if (self.logStrategy == MCLogSendStrategyDay){ // 每天程序首次启动时发送日志
        
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"YYYY-MM-dd";
        NSString *dateString = [formatter stringFromDate:[NSDate date]];
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        NSString *firstDateStr = [[userDefaults objectForKey:firstStart] copy];
        
        if (!firstDateStr || ![firstDateStr isEqualToString:dateString]) {
            NSLog(@"每天程序首次启动时发送日志");
            [userDefaults setObject:dateString forKey:firstStart];
            // 发送日志
            [self sendLogsToServer];
        }
        
    }
    
}

/*
 程序进程结束即退出程序
 */
- (void)onAppWillTerminate:(NSNotification*)notification{
    [self.timer invalidate];
    NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:self.startDate];
    
    NSLog(@"用户统计 -- 程序进程关闭-退出程序 使用时长 %.f2",duration);
    
    for (NSDictionary *classInfo in self.normalVCUse) {
        
        NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:classInfo[@"classUseDate"]];
        
        /*
         当使用过程中程序进入后台并停留一段时间时，统计时长需要减去该段时间
         */
        if (self.backDate && ([self.backDate timeIntervalSinceDate:classInfo[@"classUseDate"]] > 0)) {
            duration = duration - [[NSDate date] timeIntervalSinceDate:self.backDate];
        }
        
        NSLog(@"className:--- %@ --- 用户使用并停留  useTimeDuration: %.2f秒",classInfo[@"pageName"],duration);
        [self markStatisticLogWithLogName:classInfo[@"pageName"] Duration:duration];
    }
    
    NSString *subVCName = self.currentSubVCInfo[@"pageName"];
    if (subVCName.length > 0) {
        NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:self.currentSubVCInfo[@"classUseDate"]];
        /*
         当使用过程中程序进入后台并停留一段时间时，统计时长需要减去该段时间
         */
        if (self.backDate && ([self.backDate timeIntervalSinceDate:self.currentSubVCInfo[@"classUseDate"]] > 0)) {
            duration = duration - [[NSDate date] timeIntervalSinceDate:self.backDate];
        }
        NSLog(@"className:--- %@ --- 用户使用并停留  useTimeDuration: %.2f秒",self.currentSubVCInfo[@"pageName"],duration);
        [self markStatisticLogWithLogName:self.currentSubVCInfo[@"pageName"] Duration:duration];
    }
}

/*
 程序进入前台
 */
- (void)onAppDidBecomeActive:(NSNotification*)notification{
    NSLog(@"用户统计 -- 程序进入前台");
    self.aliveDate = [NSDate date];
    if (self.logStrategy == MCLogSendStrategyAppLaunch && self.backDate) { // 程序每次启动时发送日志
        NSTimeInterval timeGap = [[NSDate date] timeIntervalSinceDate:self.backDate];
        /*
         设置应用进入后台再回到前台为同一次启动的最大间隔时间，有效值范围0～600s
         例如设置值30s，则应用进入后台后，30s内唤醒为同一次启动
         */
        if (timeGap > self.sessionResumeInterval) {
            self.startDate = [NSDate date];
            NSLog(@"程序每次启动时发送日志");
            // 发送日志
            [self sendLogsToServer];
        }
    }
}

/*
 程序进入后台
 */
- (void)onAppDidEnterBackground:(NSNotification*)notification{
    NSLog(@"用户统计 -- 程序进入后台");
    self.backDate = [NSDate date];
}

#pragma mark get method
- (NSMutableArray *)collectionLog{
    if (!_collectionLog) {
        _collectionLog = [NSMutableArray array];
    }
    return _collectionLog;
}

- (NSMutableArray *)normalVCUse{
    if (!_normalVCUse) {
        _normalVCUse = [NSMutableArray array];
    }
    return _normalVCUse;
}

- (NSMutableDictionary *)currentSubVCInfo{
    if (!_currentSubVCInfo) {
        _currentSubVCInfo = [NSMutableDictionary dictionary];
    }
    return _currentSubVCInfo;
}

@end
