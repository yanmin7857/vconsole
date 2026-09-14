//
//  VConsoleCompat.h
//  vconsole — iOS 9 兼容垫片
//
//  背景：库原先使用 iOS 13+ 才引入的动态系统语义色（labelColor、
//  systemBackgroundColor、systemBlueColor 等）。这些 API 在 iOS 9.0 上
//  不存在，直接调用会在旧系统触发 unrecognized selector 崩溃。
//
//  本垫片把部署目标降到 iOS 9.0 的同时做等价回退：
//    · iOS 13+ 设备：返回真实动态色（暗色模式照常生效）；
//    · < iOS 13 设备：返回接近系统浅色模式的静态等价色（旧系统无暗色模式）。
//
//  使用：在用到系统色的 .m 中 #import "VConsoleCompat.h"，并把
//  UIColor.xxxColor / [UIColor xxxColor] 替换为对应的 VConsoleXxxColor() 函数调用。
//
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN


UIColor *VConsoleBackgroundColor(void);
UIColor *VConsoleSecondaryBackgroundColor(void);
UIColor *VConsoleTertiaryBackgroundColor(void);
UIColor *VConsoleGroupedBackgroundColor(void);
UIColor *VConsoleSecondaryGroupedBackgroundColor(void);
UIColor *VConsoleTertiaryGroupedBackgroundColor(void);
UIColor *VConsoleLabelColor(void);
UIColor *VConsoleSecondaryLabelColor(void);
UIColor *VConsoleTertiaryLabelColor(void);
UIColor *VConsoleQuaternaryLabelColor(void);
UIColor *VConsolePlaceholderTextColor(void);
UIColor *VConsoleSeparatorColor(void);
UIColor *VConsoleOpaqueSeparatorColor(void);
UIColor *VConsoleLinkColor(void);
UIColor *VConsoleBlueColor(void);
UIColor *VConsoleBrownColor(void);
UIColor *VConsoleCyanColor(void);
UIColor *VConsoleGreenColor(void);
UIColor *VConsoleIndigoColor(void);
UIColor *VConsoleMintColor(void);
UIColor *VConsoleOrangeColor(void);
UIColor *VConsolePinkColor(void);
UIColor *VConsolePurpleColor(void);
UIColor *VConsoleRedColor(void);
UIColor *VConsoleTealColor(void);
UIColor *VConsoleYellowColor(void);
UIColor *VConsoleGrayColor(void);
UIColor *VConsoleGray2Color(void);
UIColor *VConsoleGray3Color(void);
UIColor *VConsoleGray4Color(void);
UIColor *VConsoleGray5Color(void);
UIColor *VConsoleGray6Color(void);
UIColor *VConsoleSystemFillColor(void);
UIColor *VConsoleSecondarySystemFillColor(void);
UIColor *VConsoleTertiarySystemFillColor(void);
UIColor *VConsoleQuaternarySystemFillColor(void);

// SF Symbols 在 iOS 13 才引入；< iOS 13 无对应符号，返回 nil（调试面板图标留空）。
UIImage * _Nullable VConsoleImageNamed(NSString *name);

NS_ASSUME_NONNULL_END