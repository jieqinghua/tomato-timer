import AppKit
import SwiftUI

struct TimerMenuView: View {
    private enum MenuTab: Hashable {
        case focus
        case stats
        case settings

        var accessibilityTitle: String {
            switch self {
            case .focus:
                return "专注"
            case .stats:
                return "统计"
            case .settings:
                return "设置"
            }
        }
    }

    @ObservedObject var viewModel: TimerViewModel
    @State private var selectedTab: MenuTab = .focus
    @State private var speedRecordingDirectoryURL: URL?
    @State private var showsStartConfirmation = false
    @State private var startConfirmationTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Picker("", selection: $selectedTab) {
                    Text("专注").tag(MenuTab.focus)
                    Text("统计").tag(MenuTab.stats)
                    Text("设置").tag(MenuTab.settings)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("功能分页")
                .accessibilityValue(selectedTab.accessibilityTitle)

                Group {
                    switch selectedTab {
                    case .focus:
                        focusTab
                    case .stats:
                        statsTab
                    case .settings:
                        settingsTab
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(12)

            Divider()

            Button("退出番茄时钟") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
        }
        .frame(width: 320, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(tabKeyboardShortcuts)
        .onAppear {
            selectedTab = .focus
            refreshSpeedRecordingDirectoryURL()
        }
        .onChange(of: viewModel.status) { _, newStatus in
            guard newStatus == .running, viewModel.phase == .focus else {
                showsStartConfirmation = false
                startConfirmationTask?.cancel()
                return
            }

            showsStartConfirmation = true
            startConfirmationTask?.cancel()
            startConfirmationTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.6))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    showsStartConfirmation = false
                }
            }
        }
        .onDisappear {
            startConfirmationTask?.cancel()
        }
    }

    private var focusTab: some View {
        VStack(spacing: 30) {
            ZStack {
                if viewModel.phase == .focus, viewModel.status == .idle {
                    focusReadiness
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    activeTimerHero
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(.easeOut(duration: 0.22), value: viewModel.status)
            .animation(.easeOut(duration: 0.22), value: viewModel.phase)

            timerControls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 2)
        .padding(.vertical, 22)
    }

    private var focusReadiness: some View {
        VStack(spacing: 20) {
            VStack(spacing: 7) {
                Text("你现在状态怎么样？")
                    .font(.title3.weight(.semibold))

                Text(viewModel.selectedFocusMood.encouragement)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }

            HStack(alignment: .top, spacing: 7) {
                ForEach(Array(FocusMood.allCases.enumerated()), id: \.element.id) { index, mood in
                    moodButton(mood, shortcutNumber: index + 1)
                }
            }
            .animation(.snappy(duration: 0.24), value: viewModel.selectedFocusMood)
        }
    }

    private func moodButton(_ mood: FocusMood, shortcutNumber: Int) -> some View {
        let isSelected = viewModel.selectedFocusMood == mood

        return Button {
            viewModel.selectFocusMood(mood)
        } label: {
            VStack(spacing: 6) {
                Image(mood.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .scaleEffect(isSelected ? 1.25 : 1)
                    .frame(width: 80, height: 80)

                Text(mood.title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)

                Group {
                    if isSelected {
                        Text("专注\(mood.recommendedMinutes)分钟")
                            .foregroundStyle(tomatoRed)
                    } else {
                        Color.clear
                    }
                }
                .font(.caption2.weight(.medium).monospacedDigit())
                .frame(height: 14)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 132)
            .background(isSelected ? tomatoRed.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? tomatoRed.opacity(0.45) : Color.clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(
            KeyEquivalent(Character(String(shortcutNumber))),
            modifiers: [.option]
        )
        .accessibilityLabel("\(mood.title)，推荐 \(mood.recommendedMinutes) 分钟")
        .accessibilityHint("选择后，本轮将专注 \(mood.recommendedMinutes) 分钟")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help("\(mood.title) · \(mood.recommendedMinutes) 分钟")
    }

    private var activeTimerHero: some View {
        VStack(spacing: 7) {
            Group {
                if viewModel.phase == .focus {
                    Image(viewModel.selectedFocusMood.assetName)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "cup.and.saucer.fill")
                        .resizable()
                        .scaledToFit()
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(leafGreen)
                        .padding(12)
                }
            }
            .frame(width: 70, height: 70)

            Text(viewModel.phaseTitle)
                .font(.headline)

            Text(viewModel.formattedRemainingTime)
                .font(.system(size: 42, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            HStack(spacing: 5) {
                if showsStartConfirmation {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(leafGreen)
                        .transition(.opacity.combined(with: .scale))
                }

                Text(viewModel.supportMessage)
                    .contentTransition(.opacity)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(height: 18)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(viewModel.phaseTitle)，剩余 \(viewModel.formattedRemainingTime)。\(viewModel.supportMessage)"
        )
    }

    private var timerControls: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 34, height: 30)
            }
            .buttonStyle(.bordered)
            .help("重置")
            .keyboardShortcut("r", modifiers: [.command])
            .accessibilityLabel("重置本轮")
            .accessibilityHint("返回默认的十五分钟准备状态")

            Button {
                viewModel.toggleRunning()
            } label: {
                Label(
                    viewModel.primaryButtonTitle,
                    systemImage: viewModel.status == .running ? "pause.fill" : "play.fill"
                )
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 30)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            }
            .buttonStyle(.borderedProminent)
            .tint(tomatoRed)
            .keyboardShortcut(.space, modifiers: [])
            .controlSize(.regular)
            .frame(width: 190)
            .accessibilityLabel(viewModel.primaryButtonTitle)
            .accessibilityHint(primaryButtonAccessibilityHint)

            Button {
                viewModel.skipPhase()
            } label: {
                Image(systemName: "forward.end.fill")
                    .frame(width: 34, height: 30)
            }
            .buttonStyle(.bordered)
            .help("跳过当前阶段")
            .keyboardShortcut(.rightArrow, modifiers: [.command])
            .accessibilityLabel("跳过当前阶段")
            .accessibilityHint("提前进入下一个阶段，不记录未完成的专注")
        }
    }

    private var statsTab: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("今日统计")
                    .font(.headline)

                Text(viewModel.stats.date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            VStack(spacing: 3) {
                Text("\(viewModel.stats.completedFocusSessionsToday)")
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                Text("今日完成番茄")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(groupBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(spacing: 12) {
                statsRow(
                    title: "今日专注",
                    value: "\(viewModel.stats.focusedMinutesToday)",
                    unit: "分钟"
                )

                Divider()

                statsRow(
                    title: "累计完成",
                    value: "\(viewModel.stats.completedFocusSessionsTotal)",
                    unit: "个番茄"
                )
            }
            .padding(12)
            .background(groupBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()
        }
        .padding(8)
    }

    private var settingsTab: some View {
        ThinVerticalScrollView {
            VStack(alignment: .leading, spacing: 14) {
                settingsSection(title: "计时") {
                    VStack(spacing: 10) {
                        Stepper(value: $viewModel.breakMinutes, in: 1...60) {
                            settingRow(title: "休息时长", minutes: viewModel.breakMinutes)
                        }
                        .disabled(!viewModel.canAdjustBreakDuration)
                        .accessibilityLabel("休息时长")
                        .accessibilityValue("\(viewModel.breakMinutes) 分钟")
                        .accessibilityHint(
                            viewModel.canAdjustBreakDuration
                                ? "调整每轮专注结束后的休息时长"
                                : "本轮计时结束或重置后可以调整"
                        )

                        Divider()

                        Toggle(
                            "休息结束自动开启下一轮专注",
                            isOn: $viewModel.autoStartFocusAfterBreak
                        )
                    }
                }

                settingsSection(title: "提醒") {
                    Toggle("完成后通知", isOn: $viewModel.notifyOnCompletion)
                }

                settingsSection(title: "倍速录屏") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("专注过程开启录屏", isOn: $viewModel.recordSpeedVideo)
                            .disabled(!viewModel.canChangeSpeedRecordingSetting)

                        if !viewModel.canChangeSpeedRecordingSetting {
                            Text("本轮计时进行中，结束或重置后即可调整录屏设置")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if viewModel.recordSpeedVideo {
                            Divider()

                            Picker("录屏速率", selection: $viewModel.recordingSpeed) {
                                ForEach(ScreenRecordingSpeed.allCases) { speed in
                                    Text(speed.shortTitle).tag(speed)
                                }
                            }
                            .pickerStyle(.segmented)
                            .disabled(!viewModel.canChangeSpeedRecordingSetting)

                            Text(viewModel.recordingSpeed.storageEstimateTitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        HStack(spacing: 8) {
                            Button {
                                openSpeedRecordingSaveLocation()
                            } label: {
                                Label("打开目录", systemImage: "folder")
                                    .frame(maxWidth: .infinity)
                            }

                            Button {
                                changeSpeedRecordingSaveLocation()
                            } label: {
                                Label("更改目录", systemImage: "folder.badge.gearshape")
                                    .frame(maxWidth: .infinity)
                            }
                            .disabled(!viewModel.canChangeSpeedRecordingSetting)
                        }
                        .controlSize(.small)
                    }
                }

                if let message = viewModel.speedRecordingStatusMessage {
                    speedRecordingStatus(message)
                }
            }
            .padding(8)
        }
    }

    private var primaryButtonAccessibilityHint: String {
        switch viewModel.status {
        case .idle:
            return viewModel.phase == .focus
                ? "立即开始本轮专注"
                : "立即开始休息"
        case .running:
            return "暂停计时，稍后可以继续"
        case .paused:
            return "从当前剩余时间继续计时"
        }
    }

    private var tabKeyboardShortcuts: some View {
        HStack(spacing: 0) {
            keyboardShortcutButton("1", tab: .focus)
            keyboardShortcutButton("2", tab: .stats)
            keyboardShortcutButton("3", tab: .settings)
        }
        .frame(width: 1, height: 1)
        .clipped()
        .opacity(0.001)
        .accessibilityHidden(true)
    }

    private func keyboardShortcutButton(_ key: Character, tab: MenuTab) -> some View {
        Button("") {
            selectedTab = tab
        }
        .keyboardShortcut(KeyEquivalent(key), modifiers: [.command])
    }

    private var groupBackground: Color {
        Color.secondary.opacity(0.08)
    }

    private var tomatoRed: Color {
        Color(red: 0.82, green: 0.16, blue: 0.12)
    }

    private var leafGreen: Color {
        Color(red: 0.18, green: 0.46, blue: 0.18)
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            content()
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(groupBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func settingRow(title: String, minutes: Int, note: String? = nil) -> some View {
        HStack(spacing: 6) {
            Text(title)

            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(minutes) 分钟")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func speedRecordingStatus(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle()
                .fill(speedRecordingStatusColor(message))
                .frame(width: 7, height: 7)

            Text(message)
                .font(.caption)
                .foregroundStyle(speedRecordingStatusColor(message))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(speedRecordingStatusColor(message).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func speedRecordingStatusColor(_ message: String) -> Color {
        if message.contains("失败") || message.contains("权限") || message.contains("授权") || message.contains("拒绝") || message.contains("需要") {
            return .orange
        }

        if message.contains("已保存") {
            return .green
        }

        if message.contains("暂停") {
            return .yellow
        }

        return .blue
    }

    private func statsRow(title: String, value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()

            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func refreshSpeedRecordingDirectoryURL() {
        speedRecordingDirectoryURL = (try? SystemScreenRecordingService.recordingDirectoryURL())
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    private func openSpeedRecordingSaveLocation() {
        let directory = speedRecordingDirectoryURL
            ?? (try? SystemScreenRecordingService.recordingDirectoryURL())
            ?? FileManager.default.homeDirectoryForCurrentUser

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(directory)
        } catch {
            NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
        }
    }

    private func changeSpeedRecordingSaveLocation() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            showSpeedRecordingDirectoryPanel()
        }
    }

    private func showSpeedRecordingDirectoryPanel() {
        let panel = NSOpenPanel()
        panel.title = "选择倍速录屏保存位置"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.collectionBehavior.insert(.moveToActiveSpace)

        do {
            panel.directoryURL = try SystemScreenRecordingService.recordingDirectoryURL()
        } catch {
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        SystemScreenRecordingService.setRecordingDirectoryURL(selectedURL)
        speedRecordingDirectoryURL = selectedURL
    }
}

private struct ThinVerticalScrollView<Content: View>: NSViewRepresentable {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller = QuarterWidthScroller()

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        context.coordinator.hostingView = hostingView

        scrollView.documentView = hostingView
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            hostingView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.hostingView?.rootView = content
    }

    final class Coordinator {
        var hostingView: NSHostingView<Content>?
    }
}

private final class QuarterWidthScroller: NSScroller {
    override class func scrollerWidth(
        for controlSize: NSControl.ControlSize,
        scrollerStyle: NSScroller.Style
    ) -> CGFloat {
        NSScroller.scrollerWidth(for: controlSize, scrollerStyle: scrollerStyle) * 0.25
    }
}
