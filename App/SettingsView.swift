import SwiftUI

/// 设置界面。
///
/// 视觉对齐 macOS 系统设置（System Settings）：灰色窗口背景 + 白色圆角分组卡片、
/// 彩色圆角图标块、开关放在行尾。
/// 窗口高度随菜单项数量自适应，不滚动；菜单项极多时卡片内部才退化为可滚动列表，
/// 避免窗口超出屏幕。
struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: Layout.sectionSpacing) {
            generalCard
            itemsSection
        }
        .padding(Layout.windowPadding)
        .frame(width: Layout.windowWidth)
        .background(Color(nsColor: .windowBackgroundColor))
        // 防抖窗口内的改动在窗口关闭时立刻落盘，避免退出丢编辑。
        .onDisappear { model.flushPendingSave() }
    }

    // MARK: - 通用

    private var generalCard: some View {
        card {
            HStack(spacing: 12) {
                IconTile(symbol: "power", color: Color(nsColor: .systemBlue))
                VStack(alignment: .leading, spacing: 1) {
                    Text("启用右键菜单")
                    Text("关闭后 Finder 右键不再显示本扩展的菜单项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $model.configuration.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .padding(.horizontal, Layout.cardHorizontalPadding)
            .padding(.vertical, 12)
        }
    }

    // MARK: - 菜单项

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("菜单项")
                    .font(.subheadline.bold())
                Text("拖动排序，悬停行尾重命名 / 删除")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.addCommandItem()
                } label: {
                    Label("添加命令", systemImage: "plus")
                }
                .controlSize(.small)
                .help("添加一个在终端里执行的命令")
            }
            .padding(.horizontal, 4)

            card {
                if model.configuration.items.isEmpty {
                    itemsEmptyState
                } else {
                    itemsList
                }
            }
        }
    }

    private var itemsEmptyState: some View {
        VStack(spacing: 10) {
            Text("还没有菜单项")
                .foregroundStyle(.secondary)
            Button("恢复默认菜单项") {
                model.restoreDefaultItems()
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private var itemsList: some View {
        List {
            ForEach(model.itemBindings, id: \.wrappedValue.id) { binding in
                MenuItemRow(
                    binding: binding,
                    onCreateShortcut: { model.createDesktopShortcut(for: $0) },
                    onDelete: { model.removeItem($0) }
                )
                .listRowInsets(EdgeInsets(
                    top: 0, leading: Layout.cardHorizontalPadding,
                    bottom: 0, trailing: Layout.cardHorizontalPadding))
            }
            .onMove { model.moveItems(from: $0, to: $1) }
            .onDelete { model.removeItems(at: $0) }
        }
        .listStyle(.plain)
        .listRowSeparator(.visible)
        .scrollContentBackground(.hidden)
        // 高度按菜单项数量精确计算，窗口随内容自适应、不出现滚动条；
        // 仅当项数多到超过上限时才允许卡片内部滚动。
        .scrollDisabled(itemsListHeight <= Layout.maxItemsListHeight)
        .frame(height: min(itemsListHeight, Layout.maxItemsListHeight))
    }

    private var itemsListHeight: CGFloat {
        model.configuration.items.reduce(0) { $0 + Layout.rowHeight(for: $1) }
            + Layout.listSafetyInset
    }

    // MARK: - 分组卡片

    /// 系统设置风格的分组卡片：白色圆角底 + 细描边，窗口背景是灰色。
    @ViewBuilder
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            )
    }
}

// MARK: - 布局常量

/// 全部尺寸集中在这一处，行高计算与渲染共用，保证"窗口高度 = 内容高度"严格成立。
private enum Layout {
    static let windowWidth: CGFloat = 480
    static let windowPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 20
    static let cardCornerRadius: CGFloat = 10
    static let cardHorizontalPadding: CGFloat = 14

    static let simpleRowHeight: CGFloat = 44
    static let commandTitleHeight: CGFloat = 32
    static let commandTitleGap: CGFloat = 8
    static let commandRowVerticalPadding: CGFloat = 16
    static let commandEditorLineHeight: CGFloat = 16
    static let commandEditorChrome: CGFloat = 14

    /// 列表超过这个高度才允许内部滚动。
    static let maxItemsListHeight: CGFloat = 560
    /// 列表滚动条占用的余量，防止最后一行被裁掉。
    static let listSafetyInset: CGFloat = 4

    static func commandEditorHeight(command: String) -> CGFloat {
        let lines = command.split(separator: "\n", omittingEmptySubsequences: false).count
        return commandEditorLineHeight * CGFloat(max(2, min(6, lines))) + commandEditorChrome
    }

    static func rowHeight(for item: MenuItemConfig) -> CGFloat {
        switch item.kind {
        case .runCommand:
            return commandTitleHeight + commandTitleGap
                + commandEditorHeight(command: item.command)
                + commandRowVerticalPadding
        default:
            return simpleRowHeight
        }
    }
}

// MARK: - 彩色图标块（系统设置风格）

/// 系统设置标志性的彩色圆角图标块：SF Symbol 白字压在功能色圆角方块上。
private struct IconTile: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(color)
            )
    }
}

// MARK: - 单行菜单项

private struct MenuItemRow: View {
    let binding: Binding<MenuItemConfig>
    let onCreateShortcut: (MenuItemConfig) -> Void
    let onDelete: (MenuItemConfig) -> Void

    @State private var isEditingTitle = false
    @State private var isHovering = false
    @FocusState private var isTitleFocused: Bool

    private var item: MenuItemConfig { binding.wrappedValue }

    var body: some View {
        content
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .runCommand:
            commandRow
        default:
            simpleRow
        }
    }

    // MARK: 普通行（单行，行高固定 44）

    private var simpleRow: some View {
        HStack(spacing: 12) {
            IconTile(symbol: item.resolvedSymbolName, color: Color(nsColor: item.kind.defaultColor))
            titleView
            Spacer(minLength: 6)
            trailingControls
        }
        .frame(height: Layout.simpleRowHeight)
    }

    // MARK: 运行命令行（标题 + 命令编辑器，行高按行数计算）

    private var commandRow: some View {
        VStack(alignment: .leading, spacing: Layout.commandTitleGap) {
            HStack(spacing: 12) {
                IconTile(symbol: item.resolvedSymbolName, color: Color(nsColor: item.kind.defaultColor))
                titleView
                Spacer(minLength: 6)
                Button {
                    onCreateShortcut(item)
                } label: {
                    Label("桌面快捷方式", systemImage: "square.and.arrow.down")
                }
                .controlSize(.small)
                .help("在桌面生成可双击运行的启动脚本")
                trailingControls
            }
            .frame(height: Layout.commandTitleHeight)

            commandEditor
                .padding(.leading, 36) // 与标题对齐（图标块 24 + 间距 12）
        }
        .padding(.vertical, Layout.commandRowVerticalPadding / 2)
        .frame(height: Layout.rowHeight(for: item))
    }

    private var commandEditor: some View {
        TextEditor(text: binding.command)
            .font(.system(size: 11, design: .monospaced))
            .scrollContentBackground(.hidden)
            .frame(height: Layout.commandEditorHeight(command: item.command))
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(nsColor: .separatorColor))
            )
            .overlay(alignment: .topLeading) {
                if item.command.isEmpty {
                    Text("cd 项目目录\n启动命令")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(9)
                        .allowsHitTesting(false)
                }
            }
    }

    // MARK: 标题与行尾控件

    @ViewBuilder
    private var titleView: some View {
        if isEditingTitle {
            TextField("标题", text: binding.title)
                .textFieldStyle(.roundedBorder)
                .focused($isTitleFocused)
                .frame(maxWidth: 200)
                .onSubmit { endEditingTitle() }
                // 点到别处（切到其它控件、别的行、窗口外）就结束编辑。
                // 少了这一步，焦点虽然丢了但文本框还留着，双击重命名再也进不去。
                .onChange(of: isTitleFocused) { isFocused in
                    if !isFocused { endEditingTitle() }
                }
        } else {
            Text(item.title.isEmpty ? "未命名" : item.title)
                .foregroundStyle(item.title.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .help("双击或点右侧铅笔重命名")
                .onTapGesture(count: 2) { beginEditingTitle() }
        }
    }

    private var trailingControls: some View {
        HStack(spacing: 8) {
            // 行内编辑入口：hover 时浮现。双击重命名发现性太差，这里给一个明确按钮。
            Button {
                beginEditingTitle()
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .opacity(isHovering && !isEditingTitle ? 1 : 0)
            .help("重命名")

            // 删除入口：hover 时浮现。列表支持 ⌫ / 拖动排序，但删除没有任何可见入口，
            // 用户尤其是"添加命令"新增的项无从下手。
            Button {
                onDelete(item)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(isHovering ? Color.red : Color.secondary)
            .opacity(isHovering ? 1 : 0)
            .help("删除该菜单项")

            // 开关放行尾，与系统设置的布局习惯一致。
            Toggle("", isOn: binding.isEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .help(item.isEnabled ? "已显示在右键菜单里" : "已隐藏")
        }
    }

    private func beginEditingTitle() {
        isEditingTitle = true
        DispatchQueue.main.async { isTitleFocused = true }
    }

    private func endEditingTitle() {
        isTitleFocused = false
        isEditingTitle = false
    }
}
