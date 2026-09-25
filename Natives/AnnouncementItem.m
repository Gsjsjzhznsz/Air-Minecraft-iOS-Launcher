//
//  AnnouncementItem.m
//  Amethyst
//

#import "AnnouncementItem.h"

@implementation AnnouncementItem

+ (instancetype)itemFromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    AnnouncementItem *item = [[AnnouncementItem alloc] init];
    item.announcementId = dict[@"id"] ?: @"";
    item.title = dict[@"title"] ?: @"";
    item.date = dict[@"date"] ?: @"";
    item.summary = dict[@"summary"] ?: @"";
    item.content = dict[@"content"] ?: @"";
    item.priority = dict[@"priority"] ?: @"normal";
    // Task169：置顶字段（"pin": true / "pinned": true / "1"）。置顶项
    // 在 AnnouncementService 排序时无条件排到最前（用户点名：服务器
    // 推荐摆到第一个）。兼容 bool/字符串两种 JSON 形态。
    id pinRaw = dict[@"pin"] ?: dict[@"pinned"];
    if ([pinRaw isKindOfClass:NSNumber.class]) {
        item.pinned = [(NSNumber *)pinRaw boolValue];
    } else if ([pinRaw isKindOfClass:NSString.class]) {
        NSString *s = [(NSString *)pinRaw lowercaseString];
        item.pinned = [s isEqualToString:@"true"] || [s isEqualToString:@"1"] || [s isEqualToString:@"yes"];
    }
    item.actionURL = dict[@"action_url"] ?: @"";
    item.actionTitle = dict[@"action_title"] ?: @"";
    item.imageURL = dict[@"image_url"] ?: @"";
    return item;
}

- (NSString *)formattedDateString {
    if (self.date.length == 0) return @"";
    // 解析 ISO 日期 "2026-07-23"
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    fmt.dateFormat = @"yyyy-MM-dd";
    NSDate *date = [fmt dateFromString:self.date];
    if (!date) return self.date;

    NSDateFormatter *displayFmt = [[NSDateFormatter alloc] init];
    displayFmt.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    displayFmt.dateStyle = NSDateFormatterLongStyle;
    displayFmt.timeStyle = NSDateFormatterNoStyle;
    return [displayFmt stringFromDate:date];
}

@end
