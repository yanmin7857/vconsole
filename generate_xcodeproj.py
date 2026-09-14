#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 vconsole.xcodeproj（Objective-C，UIKit，iPhone + iPad）。
使用 Xcode 16+ 的 PBXFileSystemSynchronizedRootGroup：Sources/vconsole/（库源码）
与 Demo/（演示 App）目录下的文件会被 Xcode 自动纳入编译，无需在 pbxproj 中逐个列出。

用法: python3 generate_xcodeproj.py
"""
import hashlib
import os

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT_NAME = "vconsole"
SYNC_DIRS = ["Sources/vconsole", "Demo"]   # 相对工程根的源码目录（同步组）
BUNDLE_ID = "com.vconsole.ios"
DEPLOY_TARGET = "9.0"
XCODEPROJ = os.path.join(HERE, PROJECT_NAME + ".xcodeproj")


def uid(seed):
    # 确定性 ID（MD5 截断 24 位十六进制 = 96bit）：重复运行生成完全相同的
    # pbxproj，避免 xcodeproj 出现无意义的 git diff；96bit 空间内碰撞概率可忽略。
    return hashlib.md5(seed.encode("utf-8")).hexdigest()[:24].upper()


IDs = {
    "project": uid("project"),
    "mainGroup": uid("mainGroup"),
    "productsGroup": uid("productsGroup"),
    "frameworksGroup": uid("frameworksGroup"),
    "target": uid("target"),
    "productRef": uid("productRef"),
    "projConfList": uid("projConfList"),
    "tgtConfList": uid("tgtConfList"),
    "projDebug": uid("projDebug"),
    "projRelease": uid("projRelease"),
    "tgtDebug": uid("tgtDebug"),
    "tgtRelease": uid("tgtRelease"),
    "sourcesPhase": uid("sourcesPhase"),
    "frameworksPhase": uid("frameworksPhase"),
    "resourcesPhase": uid("resourcesPhase"),
}
sync_ids = {d: uid("syncGroup_" + d) for d in SYNC_DIRS}

FRAMEWORKS = ["UIKit", "Foundation", "Photos", "CoreGraphics", "QuartzCore", "WebKit"]

fw_refs = {fw: uid("fwref_" + fw) for fw in FRAMEWORKS}
fw_builds = {fw: uid("fwbuild_" + fw) for fw in FRAMEWORKS}

# ---------- 各 section ----------

build_file_lines = []
for fw in FRAMEWORKS:
    build_file_lines.append(
        f'\t\t{fw_builds[fw]} /* {fw}.framework in Frameworks */ = {{isa = PBXBuildFile; '
        f'fileRef = {fw_refs[fw]} /* {fw}.framework */; }};'
    )

file_ref_lines = [
    f'\t\t{IDs["productRef"]} /* {PROJECT_NAME}.app */ = {{isa = PBXFileReference; '
    f'explicitFileType = wrapper.application; includeInIndex = 0; '
    f'path = {PROJECT_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};'
]
for fw in FRAMEWORKS:
    file_ref_lines.append(
        f'\t\t{fw_refs[fw]} /* {fw}.framework */ = {{isa = PBXFileReference; '
        f'lastKnownFileType = wrapper.framework; name = {fw}.framework; '
        f'path = System/Library/Frameworks/{fw}.framework; sourceTree = SDKROOT; }};'
    )

frameworks_phase_files = " ".join(
    f'{fw_builds[fw]} /* {fw}.framework in Frameworks */,' for fw in FRAMEWORKS
)

fw_group_children = " ".join(f'{fw_refs[fw]} /* {fw}.framework */,' for fw in FRAMEWORKS)

# 注意：PBXFileSystemSynchronizedRootGroup 的 path 必须是相对其父 group 的单个路径组件，
# 因此 Sources/vconsole 拆成两层：Sources（普通 group）下挂 vconsole（同步组）；
# Demo 同步组直接挂在 mainGroup（工程根）下。两个同步组都加入 target 的
# fileSystemSynchronizedGroups，库源码与 Demo 会被一起编译进演示 App。

# ---------- 构建配置 ----------

COMMON_PROJ = """\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;
\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu11;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = %s;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
""" % DEPLOY_TARGET

TARGET_COMMON = """\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = "";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = "Info.plist";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = %s;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = NO;
""" % (BUNDLE_ID,)

pbxproj = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 77;
\tobjects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_file_lines)}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{chr(10).join(file_ref_lines)}
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
\t\t{sync_ids["Demo"]} /* Demo */ = {{isa = PBXFileSystemSynchronizedRootGroup; path = Demo; sourceTree = "<group>"; }};
\t\t{sync_ids["Sources/vconsole"]} /* vconsole */ = {{isa = PBXFileSystemSynchronizedRootGroup; path = vconsole; sourceTree = "<group>"; }};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{IDs["frameworksPhase"]} /* Frameworks */ = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (
{frameworks_phase_files}
\t\t); runOnlyForDeploymentPostprocessing = 0; }};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{IDs["mainGroup"]} = {{isa = PBXGroup; children = (
\t\t\t{sync_ids["Demo"]} /* Demo */,
\t\t\t{uid("sourcesGroup")} /* Sources */,
\t\t\t{IDs["frameworksGroup"]} /* Frameworks */,
\t\t\t{IDs["productsGroup"]} /* Products */,
\t\t); sourceTree = "<group>"; }};
\t\t{uid("sourcesGroup")} /* Sources */ = {{isa = PBXGroup; children = (
\t\t\t{sync_ids["Sources/vconsole"]} /* vconsole */,
\t\t); path = Sources; sourceTree = "<group>"; }};
\t\t{IDs["frameworksGroup"]} /* Frameworks */ = {{isa = PBXGroup; children = (
{fw_group_children}
\t\t); name = Frameworks; sourceTree = "<group>"; }};
\t\t{IDs["productsGroup"]} /* Products */ = {{isa = PBXGroup; children = (
\t\t\t{IDs["productRef"]} /* {PROJECT_NAME}.app */,
\t\t); name = Products; sourceTree = "<group>"; }};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{IDs["target"]} /* {PROJECT_NAME} */ = {{isa = PBXNativeTarget; buildConfigurationList = {IDs["tgtConfList"]} /* Build configuration list for PBXNativeTarget "{PROJECT_NAME}" */; buildPhases = (
\t\t\t{IDs["sourcesPhase"]} /* Sources */,
\t\t\t{IDs["frameworksPhase"]} /* Frameworks */,
\t\t\t{IDs["resourcesPhase"]} /* Resources */,
\t\t); buildRules = (
\t\t); dependencies = (
\t\t); fileSystemSynchronizedGroups = (
\t\t\t{sync_ids["Demo"]} /* Demo */,
\t\t\t{sync_ids["Sources/vconsole"]} /* vconsole */,
\t\t); name = {PROJECT_NAME}; productName = {PROJECT_NAME}; productReference = {IDs["productRef"]} /* {PROJECT_NAME}.app */; productType = "com.apple.product-type.application"; }};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{IDs["project"]} /* Project object */ = {{isa = PBXProject; attributes = {{
\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\tLastUpgradeCheck = 2600;
\t\t\tTargetAttributes = {{
\t\t\t\t{IDs["target"]} = {{
\t\t\t\t\tCreatedOnToolsVersion = 26.0;
\t\t\t\t}};
\t\t\t}};
\t\t}}; buildConfigurationList = {IDs["projConfList"]} /* Build configuration list for PBXProject "{PROJECT_NAME}" */; compatibilityVersion = "Xcode 15.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (
\t\t\ten,
\t\t\tBase,
\t\t\t"zh-Hans",
\t\t); mainGroup = {IDs["mainGroup"]}; minimizedProjectReferenceProxies = 1; preferredProjectObjectVersion = 77; productRefGroup = {IDs["productsGroup"]} /* Products */; projectDirPath = ""; projectRoot = ""; targets = (
\t\t\t{IDs["target"]} /* {PROJECT_NAME} */,
\t\t); }};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{IDs["resourcesPhase"]} /* Resources */ = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (
\t\t); runOnlyForDeploymentPostprocessing = 0; }};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{IDs["sourcesPhase"]} /* Sources */ = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (
\t\t); runOnlyForDeploymentPostprocessing = 0; }};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{IDs["projDebug"]} /* Debug */ = {{isa = XCBuildConfiguration; buildSettings = {{
{COMMON_PROJ}\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t}}; name = Debug; }};
\t\t{IDs["projRelease"]} /* Release */ = {{isa = XCBuildConfiguration; buildSettings = {{
{COMMON_PROJ}\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t}}; name = Release; }};
\t\t{IDs["tgtDebug"]} /* Debug */ = {{isa = XCBuildConfiguration; buildSettings = {{
{TARGET_COMMON}\t\t\t}}; name = Debug; }};
\t\t{IDs["tgtRelease"]} /* Release */ = {{isa = XCBuildConfiguration; buildSettings = {{
{TARGET_COMMON}\t\t\t}}; name = Release; }};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{IDs["projConfList"]} /* Build configuration list for PBXProject "{PROJECT_NAME}" */ = {{isa = XCConfigurationList; buildConfigurations = (
\t\t\t{IDs["projDebug"]} /* Debug */,
\t\t\t{IDs["projRelease"]} /* Release */,
\t\t); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};
\t\t{IDs["tgtConfList"]} /* Build configuration list for PBXNativeTarget "{PROJECT_NAME}" */ = {{isa = XCConfigurationList; buildConfigurations = (
\t\t\t{IDs["tgtDebug"]} /* Debug */,
\t\t\t{IDs["tgtRelease"]} /* Release */,
\t\t); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};
/* End XCConfigurationList section */
\t}};
\trootObject = {IDs["project"]} /* Project object */;
}}
"""


def write_scheme():
    scheme_dir = os.path.join(XCODEPROJ, "xcshareddata", "xcschemes")
    os.makedirs(scheme_dir, exist_ok=True)
    scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{IDs["target"]}"
               BuildableName = "{PROJECT_NAME}.app"
               BlueprintName = "{PROJECT_NAME}"
               ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{IDs["target"]}"
            BuildableName = "{PROJECT_NAME}.app"
            BlueprintName = "{PROJECT_NAME}"
            ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{IDs["target"]}"
            BuildableName = "{PROJECT_NAME}.app"
            BlueprintName = "{PROJECT_NAME}"
            ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
    with open(os.path.join(scheme_dir, PROJECT_NAME + ".xcscheme"), "w", encoding="utf-8") as f:
        f.write(scheme)


def main():
    os.makedirs(XCODEPROJ, exist_ok=True)
    with open(os.path.join(XCODEPROJ, "project.pbxproj"), "w", encoding="utf-8") as f:
        f.write(pbxproj)
    write_scheme()
    print("已生成:", os.path.join(XCODEPROJ, "project.pbxproj"))
    print("已生成 scheme:", os.path.join(XCODEPROJ, "xcshareddata/xcschemes", PROJECT_NAME + ".xcscheme"))


if __name__ == "__main__":
    main()
