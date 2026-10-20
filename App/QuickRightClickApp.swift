import AppKit
import Combine
import SwiftUI

@main
struct QuickRightClickApp: App {
    @StateObject private var model = SettingsModel()
    /// AirDrop 发送服务需要在整个会话期间被持有，否则面板可能提前消失。
    private let airDropSharer = AirDropSharer()

    var body: some Scene {
        WindowGroup("快捷右键菜单") {
            SettingsView(model: model)
                // 扩展通过 quickrightclick:// 把需要"沙盒外权限"的动作转到这里：
                // 扩展的沙盒不允许它联系终端、也不能发起 AirDrop，主程序无沙盒可以。
                .onOpenURL { url in
                    handle(url)
                }
                // 退出前把防抖窗口内还没落盘的编辑写下去。
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.flushPendingSave()
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }

    private func handle(_ url: URL) {
        switch url.host {
        case "run":
            handleRunCommandURL(url)
        case "airdrop":
            handleAirDropURL(url)
        default:
            break
        }
    }

    // MARK: - 运行命令

    private func handleRunCommandURL(_ url: URL) {
        guard url.scheme == "quickrightclick", url.host == "run",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let identifier = components.queryItems?.first(where: { $0.name == "id" })?.value,
              let itemID = UUID(uuidString: identifier) else {
            return
        }

        let configuration = model.configuration
        guard let item = configuration.items.first(where: { $0.id == itemID && $0.kind == .runCommand }) else {
            return
        }
        MenuActionExecutor.launchScript(for: item, configuration: configuration)
    }

    // MARK: - AirDrop 共享

    private func handleAirDropURL(_ url: URL) {
        let targets = MenuActionExecutor.airDropTargets(from: url)
        guard !targets.isEmpty else { return }

        // 系统 AirDrop 面板需要有一个前台应用承载，否则不会显示。
        NSApp.activate(ignoringOtherApps: true)
        airDropSharer.share(targets)
    }
}

/// AirDrop 发送会话。`NSSharingService` 的发送面板要求服务对象在展示期间存活，
/// 因此由 App 持有本对象，会话结束后再释放。
private final class AirDropSharer: NSObject, NSSharingServiceDelegate {
    private var service: NSSharingService?

    func share(_ urls: [URL]) {
        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            NSLog("QuickRightClick AirDrop 失败：系统不支持 sendViaAirDrop")
            return
        }
        service.delegate = self
        self.service = service
        service.perform(withItems: urls)
    }

    func sharingService(
        _ sharingService: NSSharingService,
        sourceWindowForShareItems items: [Any],
        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>
    ) -> NSWindow? {
        // 面板锚定到设置窗口（若已关闭则用任一窗口，都没有时交给系统定位）。
        NSApp.keyWindow ?? NSApp.windows.first
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        service = nil
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        NSLog("QuickRightClick AirDrop 失败：%@", error.localizedDescription)
        service = nil
    }
}
