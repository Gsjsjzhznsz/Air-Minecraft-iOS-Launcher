//
//  AnnouncementDetailViewController.m
//  Amethyst
//

#import "AnnouncementDetailViewController.h"
#import "AnnouncementItem.h"
#import "MarkdownParser.h"
#import "BackgroundManager.h"
#import <SafariServices/SafariServices.h>

@interface AnnouncementDetailViewController () <SFSafariViewControllerDelegate>
@property (nonatomic, strong) AnnouncementItem *item;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UITextView *contentTextView;
@property (nonatomic, strong) UIButton *actionButton;
@end

@implementation AnnouncementDetailViewController

- (instancetype)initWithAnnouncement:(AnnouncementItem *)item {
    self = [super init];
    if (self) {
        _item = item;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    // 适配自定义启动器背景
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    // 返回按钮
    UIBarButtonItem *backItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"chevron.left"]
                                                                  style:UIBarButtonItemStylePlain
                                                                 target:self
                                                                 action:@selector(backAction)];
    self.navigationItem.leftBarButtonItem = backItem;

    [self setupUI];
    [self populateData];
}

- (void)setupUI {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.scrollView];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    self.titleLabel.textColor = [UIColor labelColor];
    self.titleLabel.numberOfLines = 0;
    [self.scrollView addSubview:self.titleLabel];

    self.dateLabel = [[UILabel alloc] init];
    self.dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.dateLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    self.dateLabel.textColor = [UIColor secondaryLabelColor];
    self.dateLabel.numberOfLines = 1;
    [self.scrollView addSubview:self.dateLabel];

    self.contentTextView = [[UITextView alloc] init];
    self.contentTextView.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentTextView.editable = NO;
    self.contentTextView.scrollEnabled = NO;
    self.contentTextView.backgroundColor = [UIColor clearColor];
    self.contentTextView.textContainerInset = UIEdgeInsetsZero;
    self.contentTextView.textContainer.lineFragmentPadding = 0;
    self.contentTextView.font = [UIFont systemFontOfSize:15];
    self.contentTextView.dataDetectorTypes = UIDataDetectorTypeLink;
    [self.scrollView addSubview:self.contentTextView];

    self.actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.actionButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.actionButton.layer.cornerRadius = 10;
    self.actionButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.actionButton.clipsToBounds = YES;
    self.actionButton.backgroundColor = [UIColor systemBlueColor];
    [self.actionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.actionButton addTarget:self action:@selector(openActionURL) forControlEvents:UIControlEventTouchUpInside];
    self.actionButton.hidden = YES;
    [self.scrollView addSubview:self.actionButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.titleLabel.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:20],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.leadingAnchor constant:20],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.trailingAnchor constant:-20],

        [self.dateLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:8],
        [self.dateLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.dateLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],

        [self.contentTextView.topAnchor constraintEqualToAnchor:self.dateLabel.bottomAnchor constant:16],
        [self.contentTextView.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.contentTextView.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],

        [self.actionButton.topAnchor constraintEqualToAnchor:self.contentTextView.bottomAnchor constant:20],
        [self.actionButton.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.actionButton.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
        [self.actionButton.heightAnchor constraintEqualToConstant:44],
        [self.actionButton.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-20],
    ]];
}

- (void)populateData {
    if (!self.item) return;
    self.titleLabel.text = self.item.title ?: @"";
    self.dateLabel.text = self.item.formattedDateString ?: @"";

    // 用 MarkdownParser 渲染正文
    NSString *content = self.item.content.length > 0 ? self.item.content : self.item.summary;
    NSAttributedString *attributed = [MarkdownParser parseMarkdown:content
                                                         baseFont:[UIFont systemFontOfSize:15]];
    self.contentTextView.attributedText = attributed;

    // 若有 actionURL 显示按钮
    if (self.item.actionURL.length > 0) {
        NSString *title = self.item.actionTitle.length > 0 ? self.item.actionTitle : @"查看详情";
        [self.actionButton setTitle:title forState:UIControlStateNormal];
        self.actionButton.hidden = NO;
    } else {
        self.actionButton.hidden = YES;
    }
}

- (void)backAction {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)openActionURL {
    if (self.item.actionURL.length == 0) return;
    NSURL *url = [NSURL URLWithString:self.item.actionURL];
    if (!url) return;
    SFSafariViewController *safari = [[SFSafariViewController alloc] initWithURL:url];
    safari.delegate = self;
    safari.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:safari animated:YES completion:nil];
}

#pragma mark - SFSafariViewControllerDelegate

- (void)safariViewControllerDidFinish:(SFSafariViewController *)controller {
    [controller dismissViewControllerAnimated:YES completion:nil];
}

@end
