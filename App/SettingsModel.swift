import AppKit
import Combine
import SwiftUI

/// 设置界面的状态模型。改动合并后写盘，扩展下次显示菜单时读到的就是新配置。
@MainActor
final class SettingsModel: ObservableObject {
    /// 编辑改动合并写盘的延迟。标题、命令都是逐字符编辑，
    /// 每次击键全量写盘 + 同步脚本会让输入明显发涩，合并到一次落盘。
    private static let saveDebounce = Duration.milliseconds(300)

    @Published var configuration: MenuConfiguration {
        didSet { scheduleSave() }
    }
    /// 写盘失败原因。界面不展示，仅记日志排查。
    private(set) var saveErrorMessage: String?
    /// 桌面快捷方式的创建结果提示。界面不展示，仅记日志排查。
    private(set) var shortcutMessage: String?

    private var pendingSaveTask: Task<Void, Never>?
    private var hasPendingSave = false

    init() {
        let stored = ConfigurationStore.load()
        let migrated = stored.migratedToCurrentSchema()
        self.configuration = migrated
        if migrated != stored {
            // 属性观察器在 init 期间不触发，补上的内置项要显式落盘，
            // 否则扩展下次构建菜单读到的还是旧配置，新功能看起来没生效。
            writeToDisk()
        } else {
            // 主程序无沙盒，只有它能生成不带隔离标记的运行脚本，启动时兜底同步一次。
            MenuActionExecutor.syncScripts(for: configuration)
        }
    }

    /// 每个菜单项的可编辑绑定，顺序与配置一致，供 ForEach 逐行渲染。
    var itemBindings: [Binding<MenuItemConfig>] {
        configuration.items.indices.map { index in
            Binding<MenuItemConfig>(
                get: { [weak self] in
                    guard let self, self.configuration.items.indices.contains(index) else {
                        return MenuItemConfig(kind: .copyPath, isEnabled: false, title: "", symbolName: "", fileSuffix: "", baseName: "")
                    }
                    return self.configuration.items[index]
                },
                set: { [weak self] newValue in
                    guard let self, self.configuration.items.indices.contains(index) else { return }
                    self.configuration.items[index] = newValue
                }
            )
        }
    }

    // MARK: - 写盘

    /// 合并 300 毫秒内的连续改动，只落盘一次。
    private func scheduleSave() {
        hasPendingSave = true
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.saveDebounce)
            guard !Task.isCancelled else { return }
            self?.writeToDisk()
        }
    }

    /// 立即落盘。退出前调用，避免防抖窗口内的改动丢失。
    func flushPendingSave() {
        guard hasPendingSave else { return }
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        writeToDisk()
    }

    private func writeToDisk() {
        pendingSaveTask = nil
        hasPendingSave = false
        if let error = ConfigurationStore.save(configuration) {
            saveErrorMessage = error.localizedDescription
            NSLog("QuickRightClick 配置保存失败：%@", error.localizedDescription)
        } else {
            saveErrorMessage = nil
        }
        // 每次落盘都同步刷新运行命令脚本。
        MenuActionExecutor.syncScripts(for: configuration)
    }

    // MARK: - 菜单项编辑

    func addCommandItem() {
        configuration.items.append(
            MenuItemConfig(
                kind: .runCommand,
                isEnabled: true,
                title: "新命令",
                symbolName: "play.circle",
                command: "cd ~\necho 请在下方编辑要执行的命令"
            )
        )
    }

    /// 恢复为默认菜单项。仅在列表被删空时提供给用户，避免出现"想加回默认项只能改配置文件"的死路。
    func restoreDefaultItems() {
        configuration.items = MenuConfiguration.defaultItems
    }

    /// 在桌面生成可双击的启动脚本。之后不打开本应用、不用右键菜单也能启动项目。
    func createDesktopShortcut(for item: MenuItemConfig) {
        do {
            let desktop = ConfigurationStore.realHomeDirectory
                .appendingPathComponent("Desktop", isDirectory: true)
            let url = try MenuActionExecutor.writeDesktopShortcut(
                title: item.title, command: item.command, to: desktop)
            shortcutMessage = "已在桌面创建：\(url.lastPathComponent)"
        } catch {
            shortcutMessage = "创建失败：\(error.localizedDescription)"
        }
    }

    /// 删除单个菜单项。按 id 定位，避免行内按钮点到的是过期索引（列表随时可排序 / 删除）。
    func removeItem(_ item: MenuItemConfig) {
        configuration.items.removeAll { $0.id == item.id }
    }

    func removeItems(at offsets: IndexSet) {
        configuration.items.remove(atOffsets: offsets)
    }

    func moveItems(from source: IndexSet, to destination: Int) {
        configuration.items.move(fromOffsets: source, toOffset: destination)
    }
}
