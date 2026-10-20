import AppKit
import Foundation

/// 菜单项的行为类型。新增功能时在此登记，设置界面与扩展共用这份定义。
enum MenuActionKind: String, Codable, CaseIterable, Identifiable {
    case copyPath
    case openTerminal
    case newFile
    /// 在终端里新开窗口执行一段自定义命令。
    case runCommand
    /// 把选中的项目交给系统 AirDrop 发送。
    case shareAirDrop

    var id: String { rawValue }

    /// 图标的默认颜色（按功能区分）。
    var defaultColor: NSColor {
        switch self {
        case .copyPath: return .systemBlue
        case .openTerminal: return .systemGreen
        case .newFile: return .systemOrange
        case .runCommand: return .systemPurple
        case .shareAirDrop: return .systemTeal
        }
    }
}

/// 单个菜单项的配置。
struct MenuItemConfig: Codable, Identifiable, Equatable {
    /// 每一项的稳定标识。不能用 kind 充当：新建文件可以有多个，
    /// kind 相同会导致列表把它们当成同一行，编辑时串行。
    var id: UUID = UUID()
    var kind: MenuActionKind
    var isEnabled: Bool
    /// 菜单显示的标题。设置界面可改。
    var title: String
    /// SF Symbols 名称。设置界面可改。
    var symbolName: String
    /// 仅 `.newFile` 使用：新建文件的扩展名（不含点）。
    var fileSuffix: String
    /// 仅 `.newFile` 使用：新建文件的基础名，去重后拼上扩展名。
    var baseName: String
    /// 仅 `.runCommand` 使用：要执行的命令，可多行（通常第一行 cd 到项目目录）。
    var command: String

    init(
        kind: MenuActionKind,
        isEnabled: Bool,
        title: String,
        symbolName: String,
        fileSuffix: String = "",
        baseName: String = "",
        command: String = ""
    ) {
        self.kind = kind
        self.isEnabled = isEnabled
        self.title = title
        self.symbolName = symbolName
        self.fileSuffix = fileSuffix
        self.baseName = baseName
        self.command = command
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, isEnabled, title, symbolName, fileSuffix, baseName, command
    }

    /// 手写解码：旧版配置文件里没有 command 等新字段时兜底为默认值，
    /// 避免升级后整份配置解析失败被重置。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decode(MenuActionKind.self, forKey: .kind)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName) ?? ""
        fileSuffix = try container.decodeIfPresent(String.self, forKey: .fileSuffix) ?? ""
        baseName = try container.decodeIfPresent(String.self, forKey: .baseName) ?? ""
        command = try container.decodeIfPresent(String.self, forKey: .command) ?? ""
    }

    var symbolFallback: String {
        switch kind {
        case .copyPath: return "link"
        case .openTerminal: return "terminal"
        case .newFile: return "doc.badge.plus"
        case .runCommand: return "play.circle"
        // SF Symbols 没有 AirDrop 专用符号，用系统通用的"分享"符号。
        case .shareAirDrop: return "square.and.arrow.up"
        }
    }

    /// 符号名无效时退回该功能类型的默认符号。
    var resolvedSymbolName: String {
        NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) != nil
            ? symbolName
            : symbolFallback
    }

    /// 菜单里显示的彩色图标：SF Symbol 染色后以非模板模式渲染。
    func menuIcon() -> NSImage? {
        guard let base = NSImage(systemSymbolName: resolvedSymbolName, accessibilityDescription: title) else {
            return nil
        }
        let configuration = NSImage.SymbolConfiguration(paletteColors: [kind.defaultColor])
        let image = base.withSymbolConfiguration(configuration) ?? base
        image.isTemplate = false
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}

/// 写入磁盘的完整配置。
struct MenuConfiguration: Codable, Equatable {
    /// 配置结构版本。升级时据此只补"本次新增"的内置菜单项，
    /// 不会把用户手动删掉的内置项重新塞回来。
    /// 历史文件没有这个字段，按 0 处理，走一次补齐。
    static let currentSchemaVersion = 2

    /// 总开关。关闭后扩展返回空菜单。
    var isEnabled: Bool
    var items: [MenuItemConfig]
    /// 进入终端使用的应用，为空表示系统默认终端。
    var terminalBundleIdentifier: String
    var schemaVersion: Int = MenuConfiguration.currentSchemaVersion

    private enum CodingKeys: String, CodingKey {
        case isEnabled, items, terminalBundleIdentifier, schemaVersion
    }

    /// 手写解码：旧版配置文件没有 schemaVersion 等新字段时兜底，
    /// 避免升级后整份配置解析失败被重置。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        items = try container.decodeIfPresent([MenuItemConfig].self, forKey: .items) ?? []
        terminalBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .terminalBundleIdentifier) ?? ""
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
    }

    init(isEnabled: Bool, items: [MenuItemConfig], terminalBundleIdentifier: String, schemaVersion: Int = MenuConfiguration.currentSchemaVersion) {
        self.isEnabled = isEnabled
        self.items = items
        self.terminalBundleIdentifier = terminalBundleIdentifier
        self.schemaVersion = schemaVersion
    }

    static func makeDefault() -> MenuConfiguration {
        MenuConfiguration(
            isEnabled: true,
            items: defaultItems,
            terminalBundleIdentifier: ""
        )
    }

    /// 默认的内置菜单项，顺序即菜单默认顺序。
    static let defaultItems: [MenuItemConfig] = [
        MenuItemConfig(kind: .copyPath, isEnabled: true, title: "拷贝路径", symbolName: "link", fileSuffix: "", baseName: ""),
        MenuItemConfig(kind: .shareAirDrop, isEnabled: true, title: "AirDrop 共享", symbolName: "square.and.arrow.up", fileSuffix: "", baseName: ""),
        MenuItemConfig(kind: .openTerminal, isEnabled: true, title: "进入终端", symbolName: "terminal", fileSuffix: "", baseName: ""),
        MenuItemConfig(kind: .newFile, isEnabled: true, title: "创建 TXT", symbolName: "doc.plaintext", fileSuffix: "txt", baseName: "新建文本文档"),
        MenuItemConfig(kind: .newFile, isEnabled: true, title: "创建 Markdown", symbolName: "text.document", fileSuffix: "md", baseName: "新建 Markdown"),
    ]

    /// 把旧版配置升级到当前结构版本：补上本次新增的内置项。
    ///
    /// 只在版本落后时补一次，因此用户后来主动删掉 AirDrop 项不会再被加回来。
    func migratedToCurrentSchema() -> MenuConfiguration {
        guard schemaVersion < Self.currentSchemaVersion else { return self }

        var items = self.items
        if !items.contains(where: { $0.kind == .shareAirDrop }),
           let airDrop = Self.defaultItems.first(where: { $0.kind == .shareAirDrop }) {
            // 插在拷贝路径之后，与默认顺序保持一致。
            let anchor = items.lastIndex { $0.kind == .copyPath }
            items.insert(airDrop, at: anchor.map { $0 + 1 } ?? items.count)
        }

        return MenuConfiguration(
            isEnabled: isEnabled,
            items: items,
            terminalBundleIdentifier: terminalBundleIdentifier,
            schemaVersion: Self.currentSchemaVersion
        )
    }
}
