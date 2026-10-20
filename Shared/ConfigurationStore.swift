import Foundation

/// 配置存储。
///
/// 配置放在真实主目录的 Application Support 里，而不是扩展容器：
/// 容器与应用绑定，重新部署（删除再复制 app）时系统可能清空容器导致配置丢失；
/// 扩展通过 home-relative 沙盒例外可以读写真实主目录，主程序未开沙盒也没有障碍。
///
/// 配置文件：~/Library/Application Support/QuickRightClick/config.json
enum ConfigurationStore {
    static let fileName = "config.json"
    static let directoryName = "QuickRightClick"
    static let extensionBundleIdentifier = "com.local.QuickRightClick.Extension"

    /// 测试用：重定向存储目录，避免读写真实配置。置 nil 恢复默认。
    static var directoryURLForTesting: URL?

    /// 真实主目录。扩展的 home 被沙盒重定向到容器，getpwuid 返回的才是真实主目录。
    static var realHomeDirectory: URL {
        if let entry = getpwuid(getuid()) {
            return URL(fileURLWithPath: String(cString: entry.pointee.pw_dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var directoryURL: URL {
        directoryURLForTesting
            ?? realHomeDirectory
                .appendingPathComponent("Library/Application Support/\(directoryName)", isDirectory: true)
    }

    static var fileURL: URL {
        directoryURL.appendingPathComponent(fileName)
    }

    /// 旧版配置位置（扩展容器）。升级时迁移一次。
    private static var legacyFileURL: URL? {
        guard let entry = getpwuid(getuid()) else { return nil }
        let home = URL(fileURLWithPath: String(cString: entry.pointee.pw_dir), isDirectory: true)
        let container = home.appendingPathComponent(
            "Library/Containers/\(extensionBundleIdentifier)/Data", isDirectory: true)
        return container
            .appendingPathComponent("Library/Application Support/\(directoryName)", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// 读取配置。文件不存在或解析失败时返回默认配置，保证扩展不会因配置损坏而崩溃。
    static func load() -> MenuConfiguration {
        if let data = try? Data(contentsOf: fileURL),
           let configuration = try? JSONDecoder().decode(MenuConfiguration.self, from: data) {
            return configuration
        }
        // 新位置没有配置时，尝试从旧版容器迁移一次。
        if let legacy = legacyFileURL,
           let data = try? Data(contentsOf: legacy),
           let configuration = try? JSONDecoder().decode(MenuConfiguration.self, from: data) {
            save(configuration)
            return configuration
        }
        return .makeDefault()
    }

    /// 写入配置。返回失败原因供设置界面展示。
    @discardableResult
    static func save(_ configuration: MenuConfiguration) -> Error? {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(configuration).write(to: fileURL, options: .atomic)
            return nil
        } catch {
            return error
        }
    }
}
