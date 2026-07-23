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
