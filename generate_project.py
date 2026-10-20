#!/usr/bin/env python3
"""生成 QuickRightClick.xcodeproj。

pbxproj 中的对象 ID 必须唯一且稳定，这里按用途+路径生成 24 位十六进制 ID。
"""

import hashlib
import pathlib
import sys

ROOT = pathlib.Path(__file__).parent
PROJECT_DIR = ROOT / "QuickRightClick.xcodeproj"

APP = "QuickRightClick"
EXT = "QuickRightClickExtension"
TESTS = "QuickRightClickTests"

SHARED_FILES = [
    "Shared/MenuConfiguration.swift",
    "Shared/ConfigurationStore.swift",
    "Shared/MenuActionExecutor.swift",
]
APP_FILES = [
    "App/QuickRightClickApp.swift",
    "App/SettingsModel.swift",
    "App/SettingsView.swift",
]
APP_RESOURCES = [
    "App/Assets.xcassets",
]
TEST_FILES = [
    "App/QuickRightClickTests.swift",
]
APP_SUPPORT_FILES = [
    "App/Info.plist",
    "App/QuickRightClick.entitlements",
]
EXT_FILES = [
    "Extension/FinderSyncExtension.swift",
]
EXT_SUPPORT_FILES = [
    "Extension/Info.plist",
    "Extension/QuickRightClickExtension.entitlements",
]

FILE_TYPES = {
    ".swift": "sourcecode.swift",
    ".plist": "text.plist.xml",
    ".entitlements": "text.plist.entitlements",
    ".xcassets": "folder.assetcatalog",
}

TARGET_TYPES = {
    APP: "com.apple.product-type.application",
    EXT: "com.apple.product-type.app-extension",
    TESTS: "com.apple.product-type.bundle.unit-test",
}

PROJECT_SETTINGS = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "MACOSX_DEPLOYMENT_TARGET": "13.0",
    "SDKROOT": "macosx",
    "SWIFT_VERSION": "5.0",
}

APP_SETTINGS = {
    # 没有这项，资源目录里的 AppIcon 不会被当作应用图标，
    # Finder / 程序坞只会显示系统默认的空图标。
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "CODE_SIGN_ENTITLEMENTS": "App/QuickRightClick.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "COMBINE_HIDPI_IMAGES": "YES",
    "CODE_SIGN_IDENTITY": '"Apple Development"',
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": '""',
    "ENABLE_HARDENED_RUNTIME": "NO",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "App/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/../Frameworks",\n\t\t\t\t)',
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.local.QuickRightClick",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SWIFT_EMIT_LOC_STRINGS": "YES",
}

EXT_SETTINGS = {
    "CODE_SIGN_ENTITLEMENTS": "Extension/QuickRightClickExtension.entitlements",
    "CODE_SIGN_IDENTITY": '"Apple Development"',
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": '""',
    "ENABLE_HARDENED_RUNTIME": "NO",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "Extension/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/../Frameworks",\n\t\t\t\t\t"@executable_path/../../../../Frameworks",\n\t\t\t\t)',
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.local.QuickRightClick.Extension",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SKIP_INSTALL": "YES",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
}

TEST_SETTINGS = {
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "GENERATE_INFOPLIST_FILE": "YES",
    "MACOSX_DEPLOYMENT_TARGET": "13.0",
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.local.QuickRightClickTests",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SDKROOT": "macosx",
    "SWIFT_VERSION": "5.0",
}


def uid(*parts: str) -> str:
    return hashlib.sha1("::".join(parts).encode()).hexdigest()[:24].upper()


def name_of(path: str) -> str:
    return pathlib.PurePosixPath(path).name


class Project:
    """收集 pbxproj 对象，按 section 分类输出。"""

    def __init__(self) -> None:
        self.file_refs: dict[str, str] = {}
        self.sections: dict[str, list[str]] = {}

    def add(self, section: str, text: str) -> None:
        self.sections.setdefault(section, []).append(text)

    def file_ref(self, path: str, group_path: str = "") -> str:
        key = f"{group_path}::{path}" if group_path else path
        if key in self.file_refs:
            return self.file_refs[key]
        ref = uid("fileref", key)
        self.file_refs[key] = ref
        suffix = pathlib.PurePosixPath(path).suffix
        file_type = FILE_TYPES.get(suffix, "text")
        self.add(
            "PBXFileReference",
            f"\t\t{ref} /* {name_of(path)} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = {file_type}; path = {name_of(path)}; sourceTree = \"<group>\"; }};",
        )
        return ref

    def product_ref(self, target: str, product_name: str, file_type: str) -> str:
        ref = uid("product", target)
        self.add(
            "PBXFileReference",
            f'\t\t{ref} /* {product_name} */ = {{isa = PBXFileReference; explicitFileType = "{file_type}"; '
            f'includeInIndex = 0; path = "{product_name}"; sourceTree = BUILT_PRODUCTS_DIR; }};',
        )
        return ref

    def build_file(self, path: str, target: str, phase: str, group_path: str = "") -> str:
        ref = self.file_ref(path, group_path)
        bf = uid("buildfile", target, phase, path)
        self.add(
            "PBXBuildFile",
            f"\t\t{bf} /* {name_of(path)} in {phase} */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name_of(path)} */; }};",
        )
        return bf

    def config_list(self, owner: str, settings: dict[str, str]) -> str:
        config_list = uid("configlist", owner)
        configs = []
        for config_name in ("Debug", "Release"):
            config = uid("buildconfig", owner, config_name)
            body = "".join(f"\t\t\t\t{k} = {v};\n" for k, v in settings.items())
            self.add(
                "XCBuildConfiguration",
                f"\t\t{config} /* {config_name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n"
                f"\t\t\tbuildSettings = {{\n{body}\t\t\t}};\n\t\t\tname = {config_name};\n\t\t}};",
            )
            configs.append(f"{config} /* {config_name} */")
        self.add(
            "XCConfigurationList",
            f"\t\t{config_list} /* Build configuration list for {owner} */ = {{\n"
            f"\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n"
            + "".join(f"\t\t\t\t{c},\n" for c in configs)
            + "\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n"
            f"\t\t\tdefaultConfigurationName = Release;\n\t\t}};",
        )
        return config_list

    def native_target(
        self,
        target: str,
        product_name: str,
        product_type: str,
        product_file_type: str,
        source_files: list[str],
        resource_files: list[str],
        settings: dict[str, str],
    ) -> str:
        target_id = uid("target", target)
        sources_phase = uid("phase", target, "sources")
        frameworks_phase = uid("phase", target, "frameworks")
        resources_phase = uid("phase", target, "resources")
        config_list = self.config_list(f"target {target}", settings)
        product = self.product_ref(target, product_name, product_file_type)

        source_build_files = [
            (self.build_file(path, target, "Sources"), path) for path in source_files
        ]
        resource_build_files = [
            (self.build_file(path, target, "Resources"), path) for path in resource_files
        ]

        self.add(
            "PBXSourcesBuildPhase",
            f"\t\t{sources_phase} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n"
            f"\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n"
            + "".join(f"\t\t\t\t{bf} /* {name_of(p)} in Sources */,\n" for bf, p in source_build_files)
            + "\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};",
        )
        self.add(
            "PBXFrameworksBuildPhase",
            f"\t\t{frameworks_phase} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n"
            f"\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n"
            f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};",
        )
        self.add(
            "PBXResourcesBuildPhase",
            f"\t\t{resources_phase} /* Resources */ = {{\n\t\t\tisa = PBXResourcesBuildPhase;\n"
            f"\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n"
            + "".join(f"\t\t\t\t{bf} /* {name_of(p)} in Resources */,\n" for bf, p in resource_build_files)
            + "\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};",
        )
        self.add(
            "PBXNativeTarget",
            f"\t\t{target_id} /* {target} */ = {{\n\t\t\tisa = PBXNativeTarget;\n"
            f"\t\t\tbuildConfigurationList = {config_list};\n"
            f"\t\t\tbuildPhases = (\n"
            f"\t\t\t\t{sources_phase} /* Sources */,\n"
            f"\t\t\t\t{frameworks_phase} /* Frameworks */,\n"
            f"\t\t\t\t{resources_phase} /* Resources */,\n"
            f"\t\t\t);\n"
            f"\t\t\tbuildRules = (\n\t\t\t);\n"
            f"\t\t\tdependencies = (\n\t\t\t);\n"
            f"\t\t\tname = {target};\n"
            f"\t\t\tproductName = {target};\n"
            f"\t\t\tproductReference = {product} /* {product_name} */;\n"
            f"\t\t\tproductType = \"{product_type}\";\n\t\t}};",
        )
        return target_id

    def group(self, group_id: str, label: str, children: list[str], path: str | None) -> None:
        entries = "".join(f"\t\t\t\t{c},\n" for c in children)
        path_line = f"\t\t\tpath = {path};\n" if path else ""
        name_line = f"\t\t\tname = {label};\n" if not path else ""
        self.add(
            "PBXGroup",
            f"\t\t{group_id} /* {label} */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
            f"{entries}\t\t\t);\n{name_line}{path_line}"
            f"\t\t\tsourceTree = \"<group>\";\n\t\t}};",
        )

    def render(self) -> str:
        order = [
            "PBXBuildFile",
            "PBXContainerItemProxy",
            "PBXCopyFilesBuildPhase",
            "PBXFileReference",
            "PBXFrameworksBuildPhase",
            "PBXGroup",
            "PBXNativeTarget",
            "PBXProject",
            "PBXResourcesBuildPhase",
            "PBXSourcesBuildPhase",
            "PBXTargetDependency",
            "XCBuildConfiguration",
            "XCConfigurationList",
        ]
        chunks = []
        for section in order:
            entries = sorted(set(self.sections.get(section, [])))
            if not entries:
                continue
            chunks.append(f"/* Begin {section} section */\n" + "\n".join(entries) + f"\n/* End {section} section */")
        return "\n".join(chunks)


def main() -> int:
    p = Project()

    # ---- 分组与文件引用 ----
    shared_group = uid("group", "Shared")
    app_group = uid("group", "App")
    ext_group = uid("group", "Extension")
    products_group = uid("group", "Products")
    root_group = uid("group", "root")

    for group_id, label, files in (
        (shared_group, "Shared", SHARED_FILES),
        (app_group, "App", APP_FILES + APP_RESOURCES + APP_SUPPORT_FILES),
        (ext_group, "Extension", EXT_FILES + EXT_SUPPORT_FILES),
    ):
        p.group(group_id, label, [p.file_ref(path) + f" /* {name_of(path)} */" for path in files], label)
    # 测试代码位于 App/，group 前缀与主 App group 一致。
    tests_group = uid("group", "Tests")
    p.group(
        tests_group,
        "Tests",
        [p.file_ref(path) + f" /* {name_of(path)} */" for path in TEST_FILES],
        "App",
    )

    app_product_ref = p.product_ref(APP, f"{APP}.app", "wrapper.application")
    ext_product_ref = p.product_ref(EXT, f"{EXT}.appex", "wrapper.app-extension")
    tests_product_ref = p.product_ref(TESTS, f"{TESTS}.xctest", "wrapper.cfbundle")
    p.group(
        products_group,
        "Products",
        [
            f"{app_product_ref} /* {APP}.app */",
            f"{ext_product_ref} /* {EXT}.appex */",
            f"{tests_product_ref} /* {TESTS}.xctest */",
        ],
        None,
    )
    p.group(
        root_group,
        "QuickRightClick",
        [
            f"{shared_group} /* Shared */",
            f"{app_group} /* App */",
            f"{ext_group} /* Extension */",
            f"{tests_group} /* Tests */",
            f"{products_group} /* Products */",
        ],
        None,
    )

    # ---- target ----
    ext_target = p.native_target(
        EXT,
        f"{EXT}.appex",
        TARGET_TYPES[EXT],
        "wrapper.app-extension",
        source_files=SHARED_FILES + EXT_FILES,
        resource_files=[],
        settings=EXT_SETTINGS,
    )
    app_target = p.native_target(
        APP,
        f"{APP}.app",
        TARGET_TYPES[APP],
        "wrapper.application",
        source_files=SHARED_FILES + APP_FILES,
        resource_files=APP_RESOURCES,
        settings=APP_SETTINGS,
    )
    tests_target = p.native_target(
        TESTS,
        f"{TESTS}.xctest",
        TARGET_TYPES[TESTS],
        "wrapper.cfbundle",
        source_files=SHARED_FILES + TEST_FILES,
        resource_files=[],
        settings=TEST_SETTINGS,
    )

    # ---- 把扩展嵌入主程序 ----
    embed_build_file = uid("buildfile", APP, "Embed", EXT)
    p.add(
        "PBXBuildFile",
        f"\t\t{embed_build_file} /* {EXT}.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; "
        f"fileRef = {ext_product_ref} /* {EXT}.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};",
    )
    embed_phase = uid("phase", APP, "embed")
    p.add(
        "PBXCopyFilesBuildPhase",
        f"\t\t{embed_phase} /* Embed Foundation Extensions */ = {{\n\t\t\tisa = PBXCopyFilesBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f'\t\t\tdstPath = "";\n\t\t\tdstSubfolderSpec = 13;\n\t\t\tfiles = (\n'
        f"\t\t\t\t{embed_build_file} /* {EXT}.appex in Embed Foundation Extensions */,\n"
        f'\t\t\t);\n\t\t\tname = "Embed Foundation Extensions";\n'
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};",
    )
    embed_proxy = uid("proxy", "embed")
    p.add(
        "PBXContainerItemProxy",
        f"\t\t{embed_proxy} /* PBXContainerItemProxy */ = {{\n\t\t\tisa = PBXContainerItemProxy;\n"
        f"\t\t\tcontainerPortal = {uid('project')} /* Project object */;\n"
        f"\t\t\tproxyType = 1;\n"
        f"\t\t\tremoteGlobalIDString = {ext_target};\n"
        f"\t\t\tremoteInfo = {EXT};\n\t\t}};",
    )
    app_dependency = uid("dependency", APP)
    p.add(
        "PBXTargetDependency",
        f"\t\t{app_dependency} /* PBXTargetDependency */ = {{\n\t\t\tisa = PBXTargetDependency;\n"
        f"\t\t\ttarget = {ext_target} /* {EXT} */;\n"
        f"\t\t\ttargetProxy = {embed_proxy} /* PBXContainerItemProxy */;\n\t\t}};",
    )

    # App target 需要引用embed 阶段与依赖，重建该条目
    app_target_text = [
        line for line in p.sections["PBXNativeTarget"] if f"/* {APP} */ = {{" in line
    ][0]
    p.sections["PBXNativeTarget"] = [line for line in p.sections["PBXNativeTarget"] if line is not app_target_text]
    p.sections["PBXNativeTarget"].append(
        app_target_text.replace(
            f"\t\t\t\t{uid('phase', APP, 'resources')} /* Resources */,\n\t\t\t);",
            f"\t\t\t\t{uid('phase', APP, 'resources')} /* Resources */,\n"
            f"\t\t\t\t{embed_phase} /* Embed Foundation Extensions */,\n\t\t\t);",
        ).replace(
            "\t\t\tdependencies = (\n\t\t\t);",
            f"\t\t\tdependencies = (\n\t\t\t\t{app_dependency} /* PBXTargetDependency */,\n\t\t\t);",
        )
    )

    # ---- project ----
    project_id = uid("project")
    project_config_list = p.config_list("project", PROJECT_SETTINGS)
    p.add(
        "PBXProject",
        f"\t\t{project_id} /* Project object */ = {{\n\t\t\tisa = PBXProject;\n"
        f"\t\t\tattributes = {{\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n"
        f"\t\t\t\tLastSwiftUpdateCheck = 2630;\n\t\t\t\tLastUpgradeCheck = 2630;\n\t\t\t}};\n"
        f"\t\t\tbuildConfigurationList = {project_config_list};\n"
        f'\t\t\tcompatibilityVersion = "Xcode 15.0";\n'
        f"\t\t\tdevelopmentRegion = zh_CN;\n"
        f"\t\t\thasScannedForEncodings = 0;\n"
        f"\t\t\tknownRegions = (\n\t\t\t\tBase,\n\t\t\t\t\"zh-Hans\",\n\t\t\t);\n"
        f"\t\t\tmainGroup = {root_group};\n"
        f"\t\t\tproductRefGroup = {products_group} /* Products */;\n"
        f'\t\t\tprojectDirPath = "";\n\t\t\tprojectRoot = "";\n'
        f"\t\t\ttargets = (\n\t\t\t\t{ext_target} /* {EXT} */,\n\t\t\t\t{app_target} /* {APP} */,\n\t\t\t\t{tests_target} /* {TESTS} */,\n\t\t\t);\n\t\t}};",
    )

    content = (
        "// !$*UTF8*$!\n"
        "{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 60;\n\tobjects = {\n"
        + p.render()
        + f"\n\t}};\n\trootObject = {project_id} /* Project object */;\n}}\n"
    )

    if not PROJECT_DIR.exists():
        PROJECT_DIR.mkdir()
    (PROJECT_DIR / "project.pbxproj").write_text(content, encoding="utf-8")

    schemes = PROJECT_DIR / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    (schemes / f"{APP}.xcscheme").write_text(
        SCHEME.replace("{app_id}", app_target)
        .replace("{tests_id}", tests_target)
        .replace("{tests_name}", TESTS)
        .replace("{app}", APP),
        encoding="utf-8",
    )

    print(f"已生成 {PROJECT_DIR / 'project.pbxproj'}")
    return 0


SCHEME = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2630" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app_id}"
               BuildableName = "{app}.app"
               BlueprintName = "{app}"
               ReferencedContainer = "container:{app}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{tests_id}"
               BuildableName = "{tests_name}.xctest"
               BlueprintName = "{tests_name}"
               ReferencedContainer = "container:{app}.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_id}"
            BuildableName = "{app}.app"
            BlueprintName = "{app}"
            ReferencedContainer = "container:{app}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_id}"
            BuildableName = "{app}.app"
            BlueprintName = "{app}"
            ReferencedContainer = "container:{app}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


if __name__ == "__main__":
    sys.exit(main())
