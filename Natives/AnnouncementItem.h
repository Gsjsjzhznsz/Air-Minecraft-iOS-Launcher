//
//  AnnouncementItem.h
//  Amethyst
//
//  公告数据模型
//  数据源：general.news_url 指向的 JSON API（默认 https://amethyst.ct.ws/api/announcements.json）
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
@property (nonatomic, copy) NSString *actionURL;
@property (nonatomic, copy) NSString *actionTitle;
@property (nonatomic, copy) NSString *imageURL;

/// 从 JSON 字典创建（字段缺失时使用空串兜底）
+ (nullable instancetype)itemFromDictionary:(NSDictionary *)dict;

/// 格式化日期显示（如 "2026年7月23日"）
- (NSString *)formattedDateString;

@end

NS_ASSUME_NONNULL_END
