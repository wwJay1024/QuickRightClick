import AppKit
import FinderSync

/// Finder 同步扩展。系统在用户右键时回调 `menu(for:)`，我们在此构建菜单。
///
/// 菜单项由访达复制后使用，只有 title / action / image / enabled / tag 会被保留。
/// `representedObject` 不会保留，因此调用上下文存在实例里，用 tag 关联。
final class FinderSyncExtension: FIFinderSync {
    /// tag 到调用上下文的映射，每次构建菜单时重建。
    private var invocationByTag: [Int: MenuInvocation] = [:]

    override init() {
        super.init()
        let directories = Self.monitoredDirectories()
        FIFinderSyncController.default().directoryURLs = directories
    }

    /// 需要监控的目录。只有这些目录及其子目录里才会出现菜单。
    ///
    /// 扩展运行在沙盒里，`homeDirectoryForCurrentUser` 指向的是自己的容器，
    /// 用它会导致菜单在任何真实文件夹里都不出现。`getpwuid` 返回的才是真实主目录，
    /// FinderSync 收到这个 URL 后会为扩展授予对应的沙盒访问权限。
    private static func monitoredDirectories() -> Set<URL> {
        guard let entry = getpwuid(getuid()) else { return [] }
        let home = URL(fileURLWithPath: String(cString: entry.pointee.pw_dir), isDirectory: true)
        return [home]
    }

    // MARK: - 菜单构建

    /// 系统在用户右键时回调本方法。
    ///
    /// Objective-C 选择器是 `menuForMenuKind:`，Swift 导入后名字为 `menu(for:)`。
    /// 写成 `menuForMenuKind(_:)` 会变成一个无关的新方法，系统永远不会调用。
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        // 只在内容区右键时提供菜单，侧边栏和工具栏不注入。
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer else {
            return nil
        }

        // 右键是高频操作，上一版每次都同步读盘（读取 + JSON 解析 + 模型构造），
        // 现在读进程内缓存，只有配置文件真的变了才会重新读盘。
        let configuration = ConfigurationCache.configuration()
        guard configuration.isEnabled else { return nil }

        let controller = FIFinderSyncController.default()
        let targetedURL = controller.targetedURL()
        // 个别情况下系统会把右键所在的容器本身也塞进选中项，过滤掉，
        // 避免把"当前目录"当成"选中的文件夹"算错工作目录。
        let selectedURLs = (controller.selectedItemURLs() ?? []).filter { $0 != targetedURL }

        let menu = NSMenu()
        invocationByTag.removeAll()

        for item in configuration.items where item.isEnabled {
            let invocation = MenuInvocation(
                item: item,
                selectedURLs: selectedURLs,
                targetedURL: targetedURL
            )

            // 拷贝路径：右键空白处时回退为拷贝当前目录，两者都没有才没有意义。
            if item.kind == .copyPath && selectedURLs.isEmpty && targetedURL == nil { continue }
            // 新建文件需要一个确定的目录。
            if item.kind == .newFile && invocation.workingDirectory == nil { continue }
            // AirDrop 需要真实的选中文件：右键空白处共享目录没有意义，直接不显示该项。
            // （在停用项过滤之后再判断，保证"菜单里看不到"就是"不可用"的唯一信号。）
            if item.kind == .shareAirDrop && selectedURLs.isEmpty { continue }

            let tag = invocationByTag.count + 1
            invocationByTag[tag] = invocation
            menu.addItem(makeMenuItem(for: item, tag: tag))
        }

        return menu.items.isEmpty ? nil : menu
    }

    private func makeMenuItem(for item: MenuItemConfig, tag: Int) -> NSMenuItem {
        let menuItem = NSMenuItem(title: item.title, action: #selector(handleMenuItem(_:)), keyEquivalent: "")
        menuItem.target = self
        menuItem.tag = tag
        // 彩色图标：SF Symbol 按功能类型染色（isTemplate = false 才会显示颜色）。
        menuItem.image = item.menuIcon()
        return menuItem
    }

    // MARK: - 动作分发

    @objc private func handleMenuItem(_ sender: NSMenuItem) {
        guard let invocation = invocationByTag[sender.tag] else { return }
        // 与构建菜单共用缓存：用户右键后几秒内点击，没必要再读一次盘。
        let configuration = ConfigurationCache.configuration()
        if let error = MenuActionExecutor.perform(invocation, configuration: configuration) {
            NSLog("QuickRightClick 动作失败：\(error.localizedDescription)")
        }
    }
}

// MARK: - 配置缓存

/// 扩展进程内的配置缓存。
///
/// 用配置文件的「修改时间 + 大小」做校验：主程序每次都原子替换整个文件，
/// 写盘后这两个属性必然变化，所以缓存不会读到过期配置；
/// 属性读不到（文件不存在）时退回 TTL 兜底，避免反复尝试读盘。
private enum ConfigurationCache {
    private static let fallbackTTL: TimeInterval = 3
    private static var entry: (configuration: MenuConfiguration, modificationDate: Date?, fileSize: UInt64?, loadedAt: Date)?

    static func configuration() -> MenuConfiguration {
        let fileURL = ConfigurationStore.fileURL
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let modificationDate = attributes?[.modificationDate] as? Date
        let fileSize = (attributes?[.size] as? NSNumber)?.uint64Value

        if let entry, entry.modificationDate == modificationDate, entry.fileSize == fileSize,
           Date().timeIntervalSince(entry.loadedAt) < fallbackTTL {
            return entry.configuration
        }

        let configuration = ConfigurationStore.load()
        entry = (configuration, modificationDate, fileSize, Date())
        return configuration
    }
}
