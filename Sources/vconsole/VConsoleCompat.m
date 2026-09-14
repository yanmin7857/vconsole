//
//  VConsoleCompat.m
//  vconsole — iOS 9 兼容垫片实现
//
#import "VConsoleCompat.h"

// 浅色模式下的等价静态色（接近 iOS 13 系统语义色的浅色值）
#define VConsole_RGB(r, g, b) [UIColor colorWithRed:(r) / 255.0 green:(g) / 255.0 blue:(b) / 255.0 alpha:1.0]
#define VConsole_RGBA(r, g, b, a) [UIColor colorWithRed:(r) / 255.0 green:(g) / 255.0 blue:(b) / 255.0 alpha:(a)]


UIColor *VConsoleBackgroundColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.systemBackgroundColor;
    return VConsole_RGB(255, 255, 255);
}

UIColor *VConsoleSecondaryBackgroundColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.secondarySystemBackgroundColor;
    return VConsole_RGB(242, 242, 247);
}

UIColor *VConsoleTertiaryBackgroundColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.tertiarySystemBackgroundColor;
    return VConsole_RGB(255, 255, 255);
}

UIColor *VConsoleGroupedBackgroundColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.systemGroupedBackgroundColor;
    return VConsole_RGB(242, 242, 247);
}

UIColor *VConsoleSecondaryGroupedBackgroundColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.secondarySystemGroupedBackgroundColor;
    return VConsole_RGB(255, 255, 255);
}

UIColor *VConsoleTertiaryGroupedBackgroundColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.tertiarySystemGroupedBackgroundColor;
    return VConsole_RGB(242, 242, 247);
}

UIColor *VConsoleLabelColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.labelColor;
    return VConsole_RGB(28, 28, 30);
}

UIColor *VConsoleSecondaryLabelColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.secondaryLabelColor;
    return VConsole_RGBA(60, 60, 67, 0.6);
}

UIColor *VConsoleTertiaryLabelColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.tertiaryLabelColor;
    return VConsole_RGBA(60, 60, 67, 0.3);
}

UIColor *VConsoleQuaternaryLabelColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.quaternaryLabelColor;
    return VConsole_RGBA(60, 60, 67, 0.18);
}

UIColor *VConsolePlaceholderTextColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.placeholderTextColor;
    return VConsole_RGBA(60, 60, 67, 0.3);
}

UIColor *VConsoleSeparatorColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.separatorColor;
    return VConsole_RGBA(60, 60, 67, 0.29);
}

UIColor *VConsoleOpaqueSeparatorColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.opaqueSeparatorColor;
    return VConsole_RGB(84, 84, 86);
}

UIColor *VConsoleLinkColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.linkColor;
    return VConsole_RGB(0, 122, 255);
}

UIColor *VConsoleBlueColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.systemBlueColor;
    return VConsole_RGB(0, 122, 255);
}

UIColor *VConsoleBrownColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.systemBrownColor;
    return VConsole_RGB(162, 132, 94);
}

UIColor *VConsoleCyanColor(void) {
    if (@available(iOS 15.0, *)) return UIColor.systemCyanColor;
    return VConsole_RGB(50, 173, 230);
}

UIColor *VConsoleGreenColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.systemGreenColor;
    return VConsole_RGB(52, 199, 89);
}

UIColor *VConsoleIndigoColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.systemIndigoColor;
    return VConsole_RGB(88, 86, 214);
}

UIColor *VConsoleMintColor(void) {
    if (@available(iOS 15.0, *)) return UIColor.systemMintColor;
    return VConsole_RGB(0, 199, 190);
}

UIColor *VConsoleOrangeColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.systemOrangeColor;
    return VConsole_RGB(255, 149, 0);
}

UIColor *VConsolePinkColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.systemPinkColor;
    return VConsole_RGB(255, 45, 85);
}

UIColor *VConsolePurpleColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.systemPurpleColor;
    return VConsole_RGB(175, 82, 222);
}

UIColor *VConsoleRedColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.systemRedColor;
    return VConsole_RGB(255, 59, 48);
}

UIColor *VConsoleTealColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.systemTealColor;
    return VConsole_RGB(90, 200, 250);
}

UIColor *VConsoleYellowColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.systemYellowColor;
    return VConsole_RGB(255, 204, 0);
}

UIColor *VConsoleGrayColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.systemGrayColor;
    return VConsole_RGB(142, 142, 147);
}

UIColor *VConsoleGray2Color(void) {
    if (@available(iOS 13.0, *)) return UIColor.systemGray2Color;
    return VConsole_RGB(174, 174, 178);
}

UIColor *VConsoleGray3Color(void) {
    if (@available(iOS 13.0, *)) return UIColor.systemGray3Color;
    return VConsole_RGB(199, 199, 204);
}

UIColor *VConsoleGray4Color(void) {
    if (@available(iOS 13.0, *)) return UIColor.systemGray4Color;
    return VConsole_RGB(209, 209, 214);
}

UIColor *VConsoleGray5Color(void) {
    if (@available(iOS 13.0, *)) return UIColor.systemGray5Color;
    return VConsole_RGB(229, 229, 234);
}

UIColor *VConsoleGray6Color(void) {
    if (@available(iOS 13.0, *)) return UIColor.systemGray6Color;
    return VConsole_RGB(242, 242, 247);
}

UIColor *VConsoleSystemFillColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.systemFillColor;
    return VConsole_RGBA(120, 120, 128, 0.2);
}

UIColor *VConsoleSecondarySystemFillColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.secondarySystemFillColor;
    return VConsole_RGBA(120, 120, 128, 0.16);
}

UIColor *VConsoleTertiarySystemFillColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.tertiarySystemFillColor;
    return VConsole_RGBA(118, 118, 128, 0.12);
}

UIColor *VConsoleQuaternarySystemFillColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.quaternarySystemFillColor;
    return VConsole_RGBA(118, 118, 128, 0.08);
}

UIImage *VConsoleImageNamed(NSString *name) {
    if (@available(iOS 13.0, *)) {
        return [UIImage systemImageNamed:name];
    }
    return nil; // iOS 9 无 SF Symbols，调试面板图标留空（可接受）
}