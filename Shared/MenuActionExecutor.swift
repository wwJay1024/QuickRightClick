import AppKit
import Foundation

/// 菜单点击时携带的上下文。由扩展在构建菜单时按菜单项的 tag 存入实例，点击时取出。
///
/// 不能塞进 NSMenuItem 的 representedObject：菜单交给访达时会被复制，
/// 只有 title / action / image / enabled / tag 保留。
struct MenuInvocation {
    let item: MenuItemConfig
    /// 用户右键选中的项目。为空表示右键的是容器空白处。
    let selectedURLs: [URL]
    /// 用户右键的那个项目，即 FIFinderSyncController.targetedURL()。
    let targetedURL: URL?

    /// 动作执行时所在的目录。
    /// 右键文件夹 → 文件夹本身；右键文件 → 所在目录；右键空白处 → 当前目录。
    ///
    /// 注意：FIFinderSyncController 返回的目录 URL 不带尾斜杠，而
    /// `hasDirectoryPath` 只做字符串判断（路径是否以 / 结尾），对它恒为 false，
    /// 用它判断目录会一律退到上一级。必须真实 stat 一次。
    var workingDirectory: URL? {
        func directory(for url: URL?) -> URL? {
            guard let url else { return nil }
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            // stat 不到（路径不存在或无权限）时按文件处理、退到上一级，与旧版行为一致。
            return (exists && isDirectory.boolValue) ? url : url.deletingLastPathComponent()
        }
        return directory(for: selectedURLs.first) ?? directory(for: targetedURL)
    }
}

enum MenuActionExecutor {
    /// 执行一个菜单动作。成功返回 nil，失败返回错误。
    static func perform(_ invocation: MenuInvocation, configuration: MenuConfiguration) -> Error? {
        if invocation.item.kind != .copyPath {
            NSLog("QuickRightClick %@ 工作目录：%@", invocation.item.title,
                  invocation.workingDirectory?.path ?? "<无>")
        }
        switch invocation.item.kind {
        case .copyPath:
            return copyPath(invocation)
        case .openTerminal:
            return openTerminal(invocation, configuration: configuration)
        case .newFile:
            return createFile(invocation)
        case .runCommand:
            return runCommand(invocation, configuration: configuration)
        case .shareAirDrop:
            return shareViaAirDrop(invocation)
        }
    }

    // MARK: - 拷贝路径

    static func copyPath(_ invocation: MenuInvocation) -> Error? {
        // 有选中项拷贝选中项；右键空白处时拷贝当前目录本身。
        var urls = invocation.selectedURLs
        if urls.isEmpty, let targeted = invocation.targetedURL {
            urls = [targeted]
        }
        let paths = urls.map(\.path)
        guard !paths.isEmpty else { return MenuActionError.noSelection }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
            ? nil
            : MenuActionError.clipboardWriteFailed
    }

    // MARK: - 进入终端

    private static func openTerminal(_ invocation: MenuInvocation, configuration: MenuConfiguration) -> Error? {
        guard let directory = invocation.workingDirectory else { return MenuActionError.noTarget }

        let applicationURL: URL?
        if configuration.terminalBundleIdentifier.isEmpty {
            applicationURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        } else {
            applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: configuration.terminalBundleIdentifier)
        }
        guard let applicationURL else { return MenuActionError.terminalNotFound }

        // 把目录作为"要打开的文稿"发 odoc Apple 事件：终端收到后会在新窗口里 cd 到该目录。
        // 之前用 openConfiguration.arguments 传路径，终端并不解析命令行参数，所以总是落在主目录。
        // open 语义每次都会新开一个窗口，即使终端已经开着也不会复用旧窗口。
        let openConfiguration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([directory], withApplicationAt: applicationURL, configuration: openConfiguration) { _, error in
            if error != nil {
                // 回退：个别终端不支持"打开文件夹"，退回直接启动（目录会丢失）。
                let fallback = NSWorkspace.OpenConfiguration()
                fallback.arguments = [directory.path]
                NSWorkspace.shared.openApplication(at: applicationURL, configuration: fallback)
            }
        }
        return nil
    }

    // MARK: - 新建文件

    private static func createFile(_ invocation: MenuInvocation) -> Error? {
        guard let directory = invocation.workingDirectory else { return MenuActionError.noTarget }

        let fileURL = uniqueURL(
            in: directory,
            baseName: invocation.item.baseName.isEmpty ? "新建文件" : invocation.item.baseName,
            suffix: invocation.item.fileSuffix
        )
        do {
            try Data().write(to: fileURL)
        } catch {
            return error
        }

        // 让 Finder 定位并选中新建的文件。
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        return nil
    }

    /// 目标已存在时追加序号：新建文本文档.txt → 新建文本文档 2.txt
    static func uniqueURL(in directory: URL, baseName: String, suffix: String) -> URL {
        let fileManager = FileManager.default
        let ext = suffix.isEmpty ? "" : ".\(suffix)"

        var candidate = directory.appendingPathComponent(baseName + ext)
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(counter)\(ext)")
            counter += 1
        }
        return candidate
    }

    // MARK: - AirDrop 共享

    /// 沙盒扩展不能自己发起 AirDrop（文件读取与共享服务都在沙盒外）。
    /// 与运行命令同一条链路：扩展读配置、拼 URL，交给无沙盒的主程序执行。
    private static func shareViaAirDrop(_ invocation: MenuInvocation) -> Error? {
        let urls = airDropItems(for: invocation)
        guard !urls.isEmpty else { return MenuActionError.noSelection }
        guard let url = airDropURL(for: urls) else { return MenuActionError.noTarget }

        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                NSLog("QuickRightClick AirDrop 失败：%@", error.localizedDescription)
            }
        }
        return nil
    }

    /// 要交给 AirDrop 的项目：优先取选中项，右键空白处时退化为右键目标本身。
    static func airDropItems(for invocation: MenuInvocation) -> [URL] {
        if !invocation.selectedURLs.isEmpty { return invocation.selectedURLs }
        return invocation.targetedURL.map { [$0] } ?? []
    }

    /// 委托 URL：`quickrightclick://airdrop?path=<encoded>&path=...`
    /// 用重复的 path 参数承载多选，省去自定义分隔符与转义。
    static func airDropURL(for urls: [URL]) -> URL? {
        guard !urls.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "quickrightclick"
        components.host = "airdrop"
        components.queryItems = urls.map { URLQueryItem(name: "path", value: $0.path) }
        return components.url
    }

    /// 主程序侧解析委托 URL，拿回要共享的文件。
    static func airDropTargets(from url: URL) -> [URL] {
        guard url.scheme == "quickrightclick", url.host == "airdrop",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return []
        }
        return (components.queryItems ?? [])
            .filter { $0.name == "path" }
            .compactMap(\.value)
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0) }
    }

    // MARK: - 运行命令

    /// 沙盒限制汇总：扩展既不能给终端发 Apple 事件，也不能把文稿打开给其他应用，
    /// 自己写的脚本还会被打上移不掉的隔离标记。因此运行命令的完整链路是：
    /// 扩展发 quickrightclick://run?id=... → 主程序（无沙盒）接收 →
    /// 主程序把预生成的脚本交给配置的终端执行。
    private static func runCommand(_ invocation: MenuInvocation, configuration: MenuConfiguration) -> Error? {
        guard !normalizedShellCommand(invocation.item.command).isEmpty else {
            return MenuActionError.emptyCommand
        }

        var components = URLComponents(string: "quickrightclick://run")!
        components.queryItems = [URLQueryItem(name: "id", value: invocation.item.id.uuidString)]
        NSWorkspace.shared.open(
            components.url!,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error {
                NSLog("QuickRightClick 运行命令失败：%@", error.localizedDescription)
            }
        }
        return nil
    }

    /// 主程序侧：把运行命令的脚本交给配置的终端执行。
    /// 只有无沙盒的主程序能做这一步，扩展调不到终端。
    static func launchScript(for item: MenuItemConfig, configuration: MenuConfiguration) {
        guard item.kind == .runCommand else { return }

        let applicationURL: URL?
        if configuration.terminalBundleIdentifier.isEmpty {
            applicationURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        } else {
            applicationURL = NSWorkspace.shared
                .urlForApplication(withBundleIdentifier: configuration.terminalBundleIdentifier)
        }
        guard let applicationURL else {
            NSLog("QuickRightClick 运行命令失败：找不到终端应用")
            return
        }

        // 保证脚本与最新配置同步（顺带兜底：配置文件被手动改动过也能刷新）。
        syncScripts(for: configuration)

        let url = scriptURL(for: item.id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSLog("QuickRightClick 运行命令失败：脚本不存在 \(url.path)")
            return
        }

        NSWorkspace.shared.open(
            [url],
            withApplicationAt: applicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error {
                NSLog("QuickRightClick 运行命令失败：%@", error.localizedDescription)
            }
        }
    }

    /// 整理用户输入的命令：去掉空行和首尾空白；给含空格的 cd 路径自动加引号
    /// （zsh 里 `cd /a b/c` 会因空格报错，用户几乎总是想要引号）。
    static func normalizedShellCommand(_ command: String) -> String {
        command
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line -> String in
                guard line.hasPrefix("cd ") else { return line }
                let target = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                guard !target.isEmpty,
                      !target.hasPrefix("'"), !target.hasPrefix("\""),
                      target.contains(" ") else { return line }
                return "cd '\(target)'"
            }
            .joined(separator: "\n")
    }

    /// 脚本目录（真实主目录，主程序写入、扩展读取）。测试可重定向。
    static var scriptDirectoryOverride: URL?

    static var scriptDirectory: URL {
        scriptDirectoryOverride
            ?? ConfigurationStore.realHomeDirectory
                .appendingPathComponent("Library/Application Support/\(ConfigurationStore.directoryName)/Run", isDirectory: true)
    }

    /// 某个运行命令项对应的脚本位置。
    static func scriptURL(for itemID: UUID) -> URL {
        scriptDirectory.appendingPathComponent("run-\(itemID.uuidString).command")
    }

    /// 生成脚本内容。末尾 `exec zsh`：命令被 Ctrl-C 掐掉后窗口留在交互 shell。
    static func makeScriptContent(_ shellCommand: String) -> String {
        "#!/bin/zsh\n\n\(shellCommand)\n\nexec zsh\n"
    }

    /// 在指定目录（通常是桌面）生成可双击的启动脚本，返回脚本位置。
    /// 主程序无沙盒，写出的文件没有隔离标记，双击即可在终端里执行。
    static func writeDesktopShortcut(title: String, command: String, to directory: URL) throws -> URL {
        let shellCommand = normalizedShellCommand(command)
        guard !shellCommand.isEmpty else { throw MenuActionError.emptyCommand }

        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        var safeTitle = title.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        if safeTitle.isEmpty { safeTitle = "启动命令" }

        let url = directory.appendingPathComponent("\(safeTitle).command")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try makeScriptContent(shellCommand).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// 主程序（无沙盒）在保存配置时调用：为每个运行命令项生成脚本，
    /// 并清理已删除项的脚本。扩展不能写这些文件（会带隔离标记）。
    static func syncScripts(for configuration: MenuConfiguration) {
        let fileManager = FileManager.default
        guard (try? fileManager.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)) != nil else {
            return
        }

        var validNames = Set<String>()
        for item in configuration.items where item.kind == .runCommand {
            let command = normalizedShellCommand(item.command)
            guard !command.isEmpty else { continue }
            let url = scriptURL(for: item.id)
            validNames.insert(url.lastPathComponent)

            let content = makeScriptContent(command)
            if let existing = try? String(contentsOf: url, encoding: .utf8), existing == content {
                continue
            }
            try? content.write(to: url, atomically: true, encoding: .utf8)
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        if let files = try? fileManager.contentsOfDirectory(at: scriptDirectory, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "command" && !validNames.contains(file.lastPathComponent) {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}

enum MenuActionError: LocalizedError {
    case noSelection
    case noTarget
    case terminalNotFound
    case clipboardWriteFailed
    case emptyCommand

    var errorDescription: String? {
        switch self {
        case .noSelection: return "没有选中任何项目"
        case .noTarget: return "无法确定目标目录"
        case .terminalNotFound: return "找不到终端应用"
        case .clipboardWriteFailed: return "写入剪贴板失败"
        case .emptyCommand: return "命令为空"
        }
    }
}
