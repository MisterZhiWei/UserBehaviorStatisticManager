//
//  StatisticDBManager.m
//  测试代码创建
//
//  Created by 刘志伟 on 2017/7/31.
//  Copyright © 2017年 micheal. All rights reserved.
//

#if (defined DEBUG) || (TARGET_IPHONE_SIMULATOR) //如果当前为debug模式且用模拟器运行则输出NSLog
#define NSLog(format, ...) NSLog(format, ## __VA_ARGS__)
#else  //其他情况都不输出
#define NSLog(...) {}
#endif

#import "StatisticDBManager.h"
#import "FMDB.h"

@implementation StatisticDBManager
static FMDatabase *dataBase;

+ (StatisticDBManager *)openListData{
    if (dataBase == nil) {
        NSString *path = [NSString stringWithFormat:@"%@/Documents/StatisticDatabase.rdb",NSHomeDirectory()];
        //创建数据库
        dataBase = [FMDatabase databaseWithPath:path];
    }
    
    //打开数据库
    if ([dataBase open]) {
        //需要添加判断，等方法封装好后根据键值对进行更改
        NSString *sql;
        //文件夹 表
        /*
         StatisticName  统计名称
         StatisticDate  统计时间
         StatisticDuration 统计持续时间
         StatisticUserId 统计用户ID
         StatisticID 统计通用数据库ID
         */
        sql = [NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS statisticData (StatisticName varchar(32),StatisticDate varchar(32),StatisticDuration varchar(32),StatisticUserId varchar(32),StatisticID varchar(32))"];
        [dataBase beginTransaction];
        BOOL result = [dataBase executeUpdate:sql];
        [dataBase commit];
        
        if (result) {
            NSLog(@"创表成功");
        } else {
            NSLog(@"创表失败");
        }
    }
    StatisticDBManager *dataDB = [[StatisticDBManager alloc] init];
    
    return dataDB;
}

- (BOOL)addData:(NSDictionary *)datas{
    [dataBase beginTransaction];
    //数据采集 表
    NSString *StatisticName = [datas objectForKey:@"StatisticName"];
    NSString *StatisticDate = [datas objectForKey:@"StatisticDate"];
    NSString *StatisticDuration = [datas objectForKey:@"StatisticDuration"];
    NSString *StatisticUserId = [datas objectForKey:@"StatisticUserId"];
    NSString *StatisticID = [datas objectForKey:@"StatisticID"];
    
    [dataBase executeUpdateWithFormat:@"INSERT INTO statisticData (StatisticName,StatisticDate,StatisticDuration,StatisticUserId,StatisticID ) VALUES (%@,%@,%@,%@,%@);",StatisticName,StatisticDate,StatisticDuration,StatisticUserId,StatisticID];
    
    [dataBase commit];
    if ([dataBase hadError]) {
        return NO;
    }
    NSLog(@"添加app数据到数据库");
    
    return YES;
}

- (NSArray *)checkDataFromedataId:(NSString *)dataId{
    NSMutableDictionary *dict = nil;
    
    NSString *sql = [NSString stringWithFormat:@"select * from statisticData"];
    FMResultSet *set = [dataBase executeQuery:sql ,dataId];
    NSMutableArray *mutiAry = [NSMutableArray array];
    
    while ([set next]) {
        //获取数据
        dict = [[NSMutableDictionary alloc] initWithDictionary:[set resultDictionary]];
        [mutiAry addObject:dict];
    }
    [set close];
    NSLog(@"查找app数据from数据库");
    
    return mutiAry;
}

- (void)deleteDataWithDataId:(NSString *)dataId{
    [dataBase beginTransaction];
    [dataBase executeUpdate:@"DELETE FROM statisticData"];
    [dataBase commit];
    NSLog(@"删除app数据from数据库");
}

@end
