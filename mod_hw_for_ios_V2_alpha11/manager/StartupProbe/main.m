#import <UIKit/UIKit.h>

@interface StartupProbeAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation StartupProbeAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    CGRect bounds = UIScreen.mainScreen.bounds;
    self.window = [[UIWindow alloc] initWithFrame:bounds];

    UIViewController *controller = [[UIViewController alloc] init];
    controller.view.backgroundColor = UIColor.whiteColor;

    UILabel *label = [[UILabel alloc] init];
    label.text = [NSString stringWithFormat:@"mod_hw 启动诊断\nBuild 12 · Objective-C + UIKit\niOS：%@", UIDevice.currentDevice.systemVersion];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    label.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [controller.view addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:controller.view.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:controller.view.centerYAnchor],
        [label.leadingAnchor constraintGreaterThanOrEqualToAnchor:controller.view.leadingAnchor constant:24],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:controller.view.trailingAnchor constant:-24]
    ]];

    self.window.rootViewController = controller;
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(StartupProbeAppDelegate.class));
    }
}
