import XCTest

/// 测试 target 独立编译 Shared 下的源文件，因此无需 import 主程序模块。
/// 被测对象是配置编解码、文件名去重、调用上下文与剪贴板写入。
final class QuickRightClickTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickRightClickTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    // MARK: - 配置编解码

    func testDefaultConfigurationRoundTripsThroughJSON() throws {
        let original = MenuConfiguration.makeDefault()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MenuConfiguration.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testDefaultConfigurationItems() {
        let configuration = MenuConfiguration.makeDefault()
        XCTAssertEqual(configuration.items.map(\.kind), [.copyPath, .shareAirDrop, .openTerminal, .newFile, .newFile])
        XCTAssertEqual(configuration.items.filter { $0.kind == .newFile }.count, 2)
        XCTAssertTrue(configuration.items.allSatisfy(\.isEnabled))
        XCTAssertEqual(configuration.schemaVersion, MenuConfiguration.currentSchemaVersion)
    }

    // MARK: - 配置迁移

    /// 老用户磁盘上的配置（没有 schemaVersion、没有 AirDrop 项）升级时补上 AirDrop 项。
    func testMigrationAddsAirDropItemToLegacyConfiguration() {
        let legacy = MenuConfiguration(
            isEnabled: true,
            items: [
                MenuItemConfig(kind: .copyPath, isEnabled: true, title: "拷贝路径", symbolName: "link"),
                MenuItemConfig(kind: .openTerminal, isEnabled: true, title: "进入终端", symbolName: "terminal"),
            ],
            terminalBundleIdentifier: "com.googlecode.iterm2",
            schemaVersion: 0
        )

        let migrated = legacy.migratedToCurrentSchema()

        XCTAssertEqual(migrated.items.map(\.kind), [.copyPath, .shareAirDrop, .openTerminal])
        XCTAssertEqual(migrated.schemaVersion, MenuConfiguration.currentSchemaVersion)
        // 用户自己的设置不能被迁移覆盖。
        XCTAssertEqual(migrated.terminalBundleIdentifier, "com.googlecode.iterm2")
    }

    /// 迁移只做一次：用户后来主动删掉 AirDrop 项，不应该被重新加回来。
    func testMigrationDoesNotResurrectDeletedItem() {
        let current = MenuConfiguration(
            isEnabled: true,
            items: [MenuItemConfig(kind: .copyPath, isEnabled: true, title: "拷贝路径", symbolName: "link")],
            terminalBundleIdentifier: ""
        )

        XCTAssertEqual(current.migratedToCurrentSchema(), current)
    }

    func testMigrationKeepsExistingAirDropItemOrder() {
        var configuration = MenuConfiguration.makeDefault()
        // 用户把 AirDrop 拖到了最后，迁移不应改变顺序。
        let airDrop = configuration.items.remove(at: 1)
        configuration.items.append(airDrop)
        configuration.schemaVersion = 0

        let migrated = configuration.migratedToCurrentSchema()

        XCTAssertEqual(migrated.items.map(\.kind).last, .shareAirDrop)
        XCTAssertEqual(migrated.items.count, 5)
    }

    // MARK: - 文件名去重

    func testUniqueURLUsesBaseNameWhenNoConflict() {
        let url = MenuActionExecutor.uniqueURL(in: temporaryDirectory, baseName: "新建文本文档", suffix: "txt")
        XCTAssertEqual(url.lastPathComponent, "新建文本文档.txt")
    }

    func testUniqueURLAppendsCounterWhenFileExists() throws {
        try Data().write(to: temporaryDirectory.appendingPathComponent("新建文本文档.txt"))
        let url = MenuActionExecutor.uniqueURL(in: temporaryDirectory, baseName: "新建文本文档", suffix: "txt")
        XCTAssertEqual(url.lastPathComponent, "新建文本文档 2.txt")
    }

    func testUniqueURLIncrementsUntilFree() throws {
        try Data().write(to: temporaryDirectory.appendingPathComponent("新建文本文档.txt"))
        for index in 1...3 {
            try Data().write(to: temporaryDirectory.appendingPathComponent("新建文本文档 \(index).txt"))
        }
        let url = MenuActionExecutor.uniqueURL(in: temporaryDirectory, baseName: "新建文本文档", suffix: "txt")
        XCTAssertEqual(url.lastPathComponent, "新建文本文档 4.txt")
    }

    func testUniqueURLHandlesEmptySuffix() {
        let url = MenuActionExecutor.uniqueURL(in: temporaryDirectory, baseName: "README", suffix: "")
        XCTAssertEqual(url.lastPathComponent, "README")
    }

    // MARK: - 调用上下文

    func testWorkingDirectoryUsesParentOfSelection() throws {
        let file = temporaryDirectory.appendingPathComponent("a.txt")
        let invocation = MenuInvocation(
            item: MenuItemConfig(kind: .newFile, isEnabled: true, title: "t", symbolName: "doc", fileSuffix: "txt", baseName: "n"),
            selectedURLs: [file],
            targetedURL: nil
        )
        XCTAssertEqual(invocation.workingDirectory, temporaryDirectory)
    }

    func testWorkingDirectoryUsesSelectedFolderItself() throws {
        let folder = temporaryDirectory.appendingPathComponent("子目录", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let invocation = MenuInvocation(
            item: MenuItemConfig(kind: .newFile, isEnabled: true, title: "t", symbolName: "doc", fileSuffix: "txt", baseName: "n"),
            selectedURLs: [folder],
            targetedURL: temporaryDirectory
        )
        // 右键的是文件夹时，工作目录应是该文件夹本身，而不是它的上一级。
        XCTAssertEqual(invocation.workingDirectory, folder)
    }

    func testWorkingDirectoryFallsBackToTargetedFolder() {
        let invocation = MenuInvocation(
            item: MenuItemConfig(kind: .newFile, isEnabled: true, title: "t", symbolName: "doc", fileSuffix: "txt", baseName: "n"),
            selectedURLs: [],
            targetedURL: temporaryDirectory
        )
        XCTAssertEqual(invocation.workingDirectory, temporaryDirectory)
    }

    func testWorkingDirectoryUsesParentWhenTargetIsFile() {
        let file = temporaryDirectory.appendingPathComponent("b.txt")
        let invocation = MenuInvocation(
            item: MenuItemConfig(kind: .newFile, isEnabled: true, title: "t", symbolName: "doc", fileSuffix: "txt", baseName: "n"),
            selectedURLs: [],
            targetedURL: file
        )
        XCTAssertEqual(invocation.workingDirectory, temporaryDirectory)
    }

    /// FIFinderSyncController 返回的目录 URL 不带尾斜杠（hasDirectoryPath 为 false），
    /// 但它就是当前目录本身，绝不能因此退到上一级。这是真实场景的回归测试。
    func testWorkingDirectoryAcceptsTargetedFolderWithoutTrailingSlash() {
        let rawURL = Self.urlWithoutTrailingSlash(temporaryDirectory)
        XCTAssertFalse(rawURL.hasDirectoryPath, "前提不成立：该 URL 应当不带尾斜杠")
        let invocation = MenuInvocation(
            item: MenuItemConfig(kind: .newFile, isEnabled: true, title: "t", symbolName: "doc", fileSuffix: "txt", baseName: "n"),
            selectedURLs: [],
            targetedURL: rawURL
        )
        XCTAssertEqual(invocation.workingDirectory?.path, temporaryDirectory.path)
    }

    func testWorkingDirectoryAcceptsSelectedFolderWithoutTrailingSlash() throws {
        let folder = temporaryDirectory.appendingPathComponent("子目录", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let rawURL = Self.urlWithoutTrailingSlash(folder)
        XCTAssertFalse(rawURL.hasDirectoryPath)
        let invocation = MenuInvocation(
            item: MenuItemConfig(kind: .newFile, isEnabled: true, title: "t", symbolName: "doc", fileSuffix: "txt", baseName: "n"),
            selectedURLs: [rawURL],
            targetedURL: temporaryDirectory
        )
        XCTAssertEqual(invocation.workingDirectory?.path, folder.path)
    }

    /// 模拟 FIFinderSyncController 返回的 URL：真实目录、但没有目录标记。
    /// 新版 Foundation 的 URL(fileURLWithPath:) 会自动探测文件系统并补上目录标记，
    /// 因此必须显式传 isDirectory: false。
    private static func urlWithoutTrailingSlash(_ url: URL) -> URL {
        URL(fileURLWithPath: url.path, isDirectory: false)
    }

    // MARK: - 符号回退

    func testInvalidSymbolNameFallsBack() {
        var item = MenuItemConfig(kind: .copyPath, isEnabled: true, title: "t", symbolName: "不存在的符号", fileSuffix: "", baseName: "")
        XCTAssertEqual(item.resolvedSymbolName, item.symbolFallback)
        item.symbolName = "link"
        XCTAssertEqual(item.resolvedSymbolName, "link")
    }

    // MARK: - 配置路径

    func testConfigurationPathPointsToRealHome() {
        let path = ConfigurationStore.fileURL.path
        // 配置在真实主目录下，不在扩展容器里（容器会随重新部署被清空）。
        XCTAssertFalse(path.contains("Containers"))
        XCTAssertTrue(path.hasSuffix("Application Support/QuickRightClick/config.json"))
    }

    func testSaveAndLoadRoundTrips() throws {
        // 重定向到临时目录，测试绝不读写真实配置。
        let temporaryStore = temporaryDirectory.appendingPathComponent("Store", isDirectory: true)
        ConfigurationStore.directoryURLForTesting = temporaryStore
        defer { ConfigurationStore.directoryURLForTesting = nil }

        let configuration = MenuConfiguration.makeDefault()
        XCTAssertNil(ConfigurationStore.save(configuration))
        XCTAssertEqual(ConfigurationStore.load(), configuration)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: temporaryStore.appendingPathComponent("config.json").path))
    }

    /// 旧版配置文件没有 command 字段，解码时必须兜底为空串而不是整份重置。
    func testDecodeLegacyItemWithoutCommandField() throws {
        let json = """
        {
          "isEnabled": true,
          "items": [
            {"baseName": "", "fileSuffix": "", "id": "11111111-1111-1111-1111-111111111111",
             "isEnabled": true, "kind": "copyPath", "symbolName": "link", "title": "拷贝路径"}
          ],
          "terminalBundleIdentifier": ""
        }
        """
        let configuration = try JSONDecoder().decode(MenuConfiguration.self, from: Data(json.utf8))
        XCTAssertEqual(configuration.items.count, 1)
        XCTAssertEqual(configuration.items[0].command, "")
    }

    // MARK: - 运行命令

    func testNormalizedShellCommandQuotesCdPathWithSpaces() {
        let normalized = MenuActionExecutor.normalizedShellCommand(
            "cd /Users/you/Projects/Demo App/src\narch -arm64 npm run dev\n"
        )
        XCTAssertEqual(
            normalized,
            "cd '/Users/you/Projects/Demo App/src'\narch -arm64 npm run dev"
        )
    }

    func testNormalizedShellCommandKeepsQuotedPathsAndBlankLines() {
        let normalized = MenuActionExecutor.normalizedShellCommand(
            "cd '/a b'  \n\n  python run.py"
        )
        XCTAssertEqual(normalized, "cd '/a b'\npython run.py")
    }

    func testSyncScriptsWritesExecutableScriptAndCleansStale() throws {
        let temporaryScripts = temporaryDirectory.appendingPathComponent("Scripts", isDirectory: true)
        MenuActionExecutor.scriptDirectoryOverride = temporaryScripts
        defer { MenuActionExecutor.scriptDirectoryOverride = nil }

        let kept = MenuItemConfig(
            kind: .runCommand, isEnabled: true, title: "t", symbolName: "play.circle",
            command: "cd '/a b'\nnpm run dev"
        )
        let removed = MenuItemConfig(
            kind: .runCommand, isEnabled: true, title: "old", symbolName: "play.circle",
            command: "echo old"
        )
        // 先为两个项都生成脚本，再只同步 kept，验证 removed 的脚本被清理。
        MenuActionExecutor.syncScripts(for: MenuConfiguration(isEnabled: true, items: [kept, removed], terminalBundleIdentifier: ""))
        MenuActionExecutor.syncScripts(for: MenuConfiguration(isEnabled: true, items: [kept], terminalBundleIdentifier: ""))

        let keptURL = MenuActionExecutor.scriptURL(for: kept.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: keptURL.path))

        let content = try String(contentsOf: keptURL, encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("#!/bin/zsh\n"))
        XCTAssertTrue(content.contains("cd '/a b'"))
        XCTAssertTrue(content.contains("npm run dev"))
        XCTAssertTrue(content.hasSuffix("exec zsh\n"))

        let attributes = try FileManager.default.attributesOfItem(atPath: keptURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertTrue(permissions & 0o111 != 0, "脚本必须有可执行权限")

        XCTAssertFalse(FileManager.default.fileExists(atPath: MenuActionExecutor.scriptURL(for: removed.id).path))
    }

    func testWriteDesktopShortcutSanitizesTitleAndIsExecutable() throws {
        let url = try MenuActionExecutor.writeDesktopShortcut(
            title: "启动/本地:演示项目", command: "cd '/a b'\npython main.py",
            to: temporaryDirectory)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(url.lastPathComponent, "启动-本地-演示项目.command")
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("python main.py"))
        XCTAssertTrue(content.hasSuffix("exec zsh\n"))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertTrue(permissions & 0o111 != 0)
    }

    // MARK: - 拷贝路径

    func testCopyPathJoinsMultipleURLsWithNewline() throws {
        let first = temporaryDirectory.appendingPathComponent("1.txt")
        let second = temporaryDirectory.appendingPathComponent("2.txt")
        let invocation = MenuInvocation(
            item: MenuItemConfig(kind: .copyPath, isEnabled: true, title: "t", symbolName: "link", fileSuffix: "", baseName: ""),
            selectedURLs: [first, second],
            targetedURL: nil
        )
        XCTAssertNil(MenuActionExecutor.copyPath(invocation))
        XCTAssertEqual(
            NSPasteboard.general.string(forType: .string),
            "\(first.path)\n\(second.path)"
        )
    }

    func testCopyPathWithoutSelectionCopiesTargetedFolder() {
        let invocation = MenuInvocation(
            item: MenuItemConfig(kind: .copyPath, isEnabled: true, title: "t", symbolName: "link", fileSuffix: "", baseName: ""),
            selectedURLs: [],
            targetedURL: temporaryDirectory
        )
        // 右键空白处时回退为拷贝当前目录本身。
        XCTAssertNil(MenuActionExecutor.copyPath(invocation))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), temporaryDirectory.path)
    }

    func testCopyPathWithoutAnythingReturnsError() {
        let invocation = MenuInvocation(
            item: MenuItemConfig(kind: .copyPath, isEnabled: true, title: "t", symbolName: "link", fileSuffix: "", baseName: ""),
            selectedURLs: [],
            targetedURL: nil
        )
        XCTAssertNotNil(MenuActionExecutor.copyPath(invocation))
    }

    // MARK: - AirDrop 委托

    private var airDropItem: MenuItemConfig {
        MenuItemConfig(kind: .shareAirDrop, isEnabled: true, title: "AirDrop 共享", symbolName: "square.and.arrow.up")
    }

    /// 多选文件必须全部出现在委托 URL 里（含空格与中文路径，不丢转义）。
    func testAirDropURLCarriesEverySelectedPath() throws {
        let urls = [
            temporaryDirectory.appendingPathComponent("报告 1.pdf"),
            temporaryDirectory.appendingPathComponent("截图.png"),
        ]

        let url = try XCTUnwrap(MenuActionExecutor.airDropURL(for: urls))

        XCTAssertEqual(url.scheme, "quickrightclick")
        XCTAssertEqual(url.host, "airdrop")
        XCTAssertEqual(MenuActionExecutor.airDropTargets(from: url).map(\.path), urls.map(\.path))
    }

    func testAirDropURLWithoutItemsIsNil() {
        XCTAssertNil(MenuActionExecutor.airDropURL(for: []))
    }

    /// 右键空白处没有选中项时，退化为共享右键目标（当前目录）本身。
    func testAirDropItemsFallBackToTargetedURL() {
        let invocation = MenuInvocation(item: airDropItem, selectedURLs: [], targetedURL: temporaryDirectory)
        XCTAssertEqual(MenuActionExecutor.airDropItems(for: invocation), [temporaryDirectory])
    }

    func testAirDropItemsPreferSelection() {
        let selected = temporaryDirectory.appendingPathComponent("a.txt")
        let invocation = MenuInvocation(item: airDropItem, selectedURLs: [selected], targetedURL: temporaryDirectory)
        XCTAssertEqual(MenuActionExecutor.airDropItems(for: invocation), [selected])
    }

    func testAirDropTargetsIgnoresForeignURLs() {
        XCTAssertTrue(MenuActionExecutor.airDropTargets(from: URL(string: "quickrightclick://run?id=x")!).isEmpty)
        XCTAssertTrue(MenuActionExecutor.airDropTargets(from: URL(string: "https://example.com")!).isEmpty)
    }
}
