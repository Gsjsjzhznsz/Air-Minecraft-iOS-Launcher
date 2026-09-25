//
//  AnnouncementItem.h
//  Amethyst
//
//  公告数据模型
//  数据源：general.news_url 指向的 JSON（Task 130 起默认为本仓库托管的
//  announcements.json：raw.githubusercontent.com 主源 + jsDelivr 镜像级联）
//  字段映射：
//    id            -> announcementId
//    title         -> title
//    date          -> date        (ISO 日期，如 "2026-07-23")
//    summary       -> summary
//    content       -> content     (Markdown 正文)
//    priority      -> priority    ("high" / "normal" / "low")
//    action_url    -> actionURL
//    action_title  -> actionTitle
//    image_url     -> imageURL
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AnnouncementItem : NSObject

@property (nonatomic, copy) NSString *announcementId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *date;        // ISO 日期字符串，如 "2026-07-23"
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, copy) NSString *content;     // Markdown 格式正文
@property (nonatomic, copy) NSString *priority;    // "high" / "normal" / "low"
/// Task169：置顶（JSON "pin": true）。置顶项无条件排到公告列表最前
///（用户点名：服务器推荐摆到第一个），其余仍按日期降序。
@property (nonatomic, assign) BOOL pinned;
@property (nonatomic, copy) NSString *actionURL;
@property (nonatomic, copy) NSString *actionTitle;
@property (nonatomic, copy) NSString *imageURL;

/// 从 JSON 字典创建（字段缺失时使用空串兜底）
+ (nullable instancetype)itemFromDictionary:(NSDictionary *)dict;

/// 格式化日期显示（如 "2026年7月23日"）
- (NSString *)formattedDateString;

@end

NS_ASSUME_NONNULL_END
