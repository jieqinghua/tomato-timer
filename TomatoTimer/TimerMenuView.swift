import AppKit
import SwiftUI

struct TimerMenuView: View {
    private enum MenuTab {
        case timer
        case stats
    }

    @ObservedObject var viewModel: TimerViewModel
    @State private var selectedTab: MenuTab = .timer
    @State private var speedRecordingDirectoryURL: URL?

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $selectedTab) {
                Text("计时").tag(MenuTab.timer)
                Text("统计").tag(MenuTab.stats)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch selectedTab {
                case .timer:
                    timerTab
                case .stats:
                    statsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 300, height: 440)
        .padding(12)
        .onAppear {
            refreshSpeedRecordingDirectoryURL()
        }
    }

    private var timerTab: some View {
        ThinVerticalScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 7) {
                    Text(viewModel.phaseTitle)
                        .font(.headline)

                    Text(viewModel.formattedRemainingTime)
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

                HStack(spacing: 8) {
                    Button {
                        viewModel.reset()
                    } label: {
                        Label("重置", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(width: 60)

                    Button {
                        viewModel.toggleRunning()
                    } label: {
                        Label(
                            viewModel.primaryButtonTitle,
                            systemImage: viewModel.status == .running ? "pause.fill" : "play.fill"
                        )
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.space, modifiers: [])
                    .controlSize(.regular)
                    .frame(width: 144)

                    Button {
                        viewModel.skipPhase()
                    } label: {
                        Label("跳过", systemImage: "forward.end.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(width: 60)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("时长")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        Stepper(value: $viewModel.focusMinutes, in: 1...180) {
                            settingRow(title: "专注", minutes: viewModel.focusMinutes)
                        }

                        Stepper(value: $viewModel.breakMinutes, in: 1...60) {
                            settingRow(title: "休息", minutes: viewModel.breakMinutes)
                        }
                    }
                    .padding(10)
                    .background(groupBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text("选项")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 9) {
                        Toggle("开启通知提醒", isOn: $viewModel.notifyOnCompletion)

                        HStack(spacing: 8) {
                            Toggle("倍速录屏", isOn: $viewModel.recordSpeedVideo)
                                .disabled(!viewModel.canChangeSpeedRecordingSetting)

                            Spacer(minLength: 4)

                            Button("打开目录") {
                                openSpeedRecordingSaveLocation()
                            }
                            .controlSize(.small)

                            Button("更改目录") {
                                changeSpeedRecordingSaveLocation()
                            }
                            .controlSize(.small)
                            .disabled(!viewModel.canChangeSpeedRecordingSetting)
                        }

                        if viewModel.recordSpeedVideo {
                            HStack(spacing: 8) {
                                Text("录屏速率")

                                Spacer(minLength: 8)

                                HStack(spacing: 0) {
                                    ForEach(ScreenRecordingSpeed.allCases) { speed in
                                        if speed != .five {
                                            Divider()
                                                .frame(height: 14)
                                        }

                                        Button {
                                            viewModel.recordingSpeed = speed
                                        } label: {
                                            Text(speed.shortTitle)
                                                .font(.caption.weight(
                                                    viewModel.recordingSpeed == speed ? .semibold : .regular
                                                ))
                                                .foregroundStyle(
                                                    viewModel.recordingSpeed == speed ? Color.white : Color.primary
                                                )
                                                .frame(width: 40, height: 22)
                                                .background(
                                                    viewModel.recordingSpeed == speed ? Color.accentColor : Color.clear
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .help(speed.storageEstimateTitle)
                                    }
                                }
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                                }
                                .disabled(!viewModel.canChangeSpeedRecordingSetting)
                            }
                        }
                    }
                    .padding(10)
                    .background(groupBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if let message = viewModel.speedRecordingStatusMessage {
                    speedRecordingStatus(message)
                }

                Divider()

                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(8)
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

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(8)
    }

    private var groupBackground: Color {
        Color.secondary.opacity(0.08)
    }

    private func settingRow(title: String, minutes: Int) -> some View {
        HStack {
            Text(title)
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
