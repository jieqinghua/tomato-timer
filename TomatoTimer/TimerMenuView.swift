import AppKit
import SwiftUI

private enum TomatoTypography {
    static let contentScale: CGFloat = 0.75
    static let small: CGFloat = 14
    static let heading: CGFloat = 20
    static let display: CGFloat = 48

    static let scaledSmall = small / contentScale
    static let scaledHeading = heading / contentScale
    static let scaledDisplay = display / contentScale
}

struct TimerMenuView: View {
    enum MenuTab: String, CaseIterable, Hashable {
        case focus = "专注"
        case stats = "统计"
        case settings = "设置"
    }

    @ObservedObject var viewModel: TimerViewModel
    private let initialTab: MenuTab
    @State private var selectedTab: MenuTab
    @State private var hoveredTab: MenuTab?
    @State private var isExitHovered = false
    @State private var speedRecordingDirectoryURL: URL?

    init(viewModel: TimerViewModel, initialTab: MenuTab = .focus) {
        self.viewModel = viewModel
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            segmentTabs
                .padding(.horizontal, 28)
                .padding(.top, 28)

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

            exitFooter
        }
        .frame(width: 388, height: 660)
        .background {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(TomatoPalette.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(TomatoPalette.border, lineWidth: 1)
                }
                .shadow(color: TomatoPalette.shadow.opacity(0.18), radius: 36, y: 20)
                .shadow(color: .white.opacity(0.72), radius: 1, y: -1)
        }
        .overlay {
            GrainOverlay()
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .allowsHitTesting(false)
        }
        .scaleEffect(TomatoTypography.contentScale, anchor: .topLeading)
        .frame(width: 291, height: 495, alignment: .topLeading)
        .background(Color.clear)
        .onAppear {
            selectedTab = initialTab
            viewModel.refreshReadyEncouragement()
            refreshSpeedRecordingDirectoryURL()
        }
        .background(tabKeyboardShortcuts)
    }

    private var segmentTabs: some View {
        HStack(spacing: 3) {
            ForEach(MenuTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: TomatoTypography.scaledSmall, weight: selectedTab == tab ? .semibold : .medium))
                        .foregroundStyle(selectedTab == tab ? .white : TomatoPalette.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .background {
                            if selectedTab == tab {
                                Capsule()
                                    .fill(TomatoPalette.primaryGradient)
                                    .overlay {
                                        Capsule()
                                            .stroke(.white.opacity(0.42), lineWidth: 0.8)
                                    }
                                    .shadow(color: TomatoPalette.red.opacity(0.26), radius: 8, y: 4)
                            } else if hoveredTab == tab {
                                Capsule()
                                    .fill(TomatoPalette.red.opacity(0.075))
                                    .overlay {
                                        Capsule()
                                            .stroke(.white.opacity(0.52), lineWidth: 0.7)
                                    }
                            }
                        }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onHover { isHovering in
                    withAnimation(.easeOut(duration: 0.14)) {
                        hoveredTab = isHovering ? tab : (hoveredTab == tab ? nil : hoveredTab)
                    }
                }
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(height: 48)
        .background {
            Capsule()
                .fill(TomatoPalette.segmentBackground)
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.7), lineWidth: 0.8)
                }
                .shadow(color: TomatoPalette.shadow.opacity(0.08), radius: 6, y: 3)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("功能分页")
    }

    private var focusTab: some View {
        Group {
            if viewModel.phase == .focus, viewModel.status == .idle {
                readinessState
                    .transition(.opacity)
            } else {
                runningState
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.24), value: viewModel.status)
        .animation(.easeOut(duration: 0.24), value: viewModel.phase)
    }

    private var readinessState: some View {
        focusStateLayout(
            title: viewModel.readyEncouragement,
            ringStyle: .ready,
            mascotAssetName: viewModel.focusMascotAssetName
        ) {
            TimeSetupControls(viewModel: viewModel)
        }
    }

    private var runningState: some View {
        focusStateLayout(
            title: viewModel.phase == .focus ? "专注中" : "休息中",
            ringStyle: .running,
            mascotAssetName: viewModel.phase == .focus ? viewModel.focusMascotAssetName : "TomatoSteady"
        ) {
            RunningControls(viewModel: viewModel)
        }
    }

    private func focusStateLayout<Controls: View>(
        title: String,
        ringStyle: TimerRingStyle,
        mascotAssetName: String,
        @ViewBuilder controls: () -> Controls
    ) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: TomatoTypography.scaledHeading, weight: .semibold, design: .rounded))
                .foregroundStyle(TomatoPalette.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(height: 30)
                .padding(.top, 50)

            Spacer(minLength: 18)

            TimerRing(
                style: ringStyle,
                mascotAssetName: mascotAssetName,
                time: viewModel.formattedRemainingTime,
                durationFraction: viewModel.hourRingFraction
            )
            .frame(width: 296, height: 296)

            Spacer(minLength: 22)

            controls()
                .frame(height: 68)
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
        }
    }

    private var statsTab: some View {
        VStack(spacing: 18) {
            Text("今日专注")
                .font(.system(size: TomatoTypography.scaledHeading, weight: .semibold, design: .rounded))
                .foregroundStyle(TomatoPalette.primaryText)
                .padding(.top, 48)

            VStack(spacing: 4) {
                Text("\(viewModel.stats.completedFocusSessionsToday)")
                    .font(.system(size: TomatoTypography.scaledDisplay, weight: .semibold, design: .rounded))
                    .foregroundStyle(TomatoPalette.red)
                    .monospacedDigit()

                Text("个番茄")
                    .font(.system(size: TomatoTypography.scaledSmall, weight: .medium))
                    .foregroundStyle(TomatoPalette.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .softCard(cornerRadius: 26)

            VStack(spacing: 0) {
                statsRow(title: "今日累计", value: "\(viewModel.stats.focusedMinutesToday) 分钟")
                Divider().overlay(TomatoPalette.border)
                statsRow(title: "累计完成", value: "\(viewModel.stats.completedFocusSessionsTotal) 个")
            }
            .softCard(cornerRadius: 22)

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
    }

    private var settingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsSection("计时") {
                    Stepper(value: $viewModel.breakMinutes, in: 1...60) {
                        settingRow(title: "休息时长", value: "\(viewModel.breakMinutes) 分钟")
                    }
                    .disabled(!viewModel.canAdjustBreakDuration)

                    Divider().overlay(TomatoPalette.border)

                    Toggle("休息结束自动开始专注", isOn: $viewModel.autoStartFocusAfterBreak)
                        .tint(TomatoPalette.red)
                }

                settingsSection("提醒") {
                    Toggle("完成后通知", isOn: $viewModel.notifyOnCompletion)
                        .tint(TomatoPalette.red)
                }

                settingsSection("倍速录屏") {
                    Toggle("专注过程开启录屏", isOn: $viewModel.recordSpeedVideo)
                        .tint(TomatoPalette.red)
                        .disabled(!viewModel.canChangeSpeedRecordingSetting)

                    if viewModel.recordSpeedVideo {
                        Divider().overlay(TomatoPalette.border)

                        Picker("录屏速率", selection: $viewModel.recordingSpeed) {
                            ForEach(ScreenRecordingSpeed.allCases) { speed in
                                Text(speed.shortTitle).tag(speed)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(TomatoPalette.red)
                        .disabled(!viewModel.canChangeSpeedRecordingSetting)
                    }

                    Divider().overlay(TomatoPalette.border)

                    HStack(spacing: 10) {
                        Button("打开目录", action: openSpeedRecordingSaveLocation)
                        Button("更改目录", action: changeSpeedRecordingSaveLocation)
                            .disabled(!viewModel.canChangeSpeedRecordingSetting)
                    }
                    .buttonStyle(.bordered)
                    .tint(TomatoPalette.red)
                }

            }
            .padding(.horizontal, 28)
            .padding(.vertical, 30)
        }
        .scrollIndicators(.hidden)
    }

    private var exitFooter: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(TomatoPalette.border)

            Button("退出番茄时钟") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: TomatoTypography.scaledSmall, weight: .medium))
            .foregroundStyle(isExitHovered ? TomatoPalette.primaryText : TomatoPalette.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(TomatoPalette.red.opacity(isExitHovered ? 0.045 : 0))
            .contentShape(Rectangle())
            .onHover { isExitHovered = $0 }
            .accessibilityHint("退出应用")
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
        Button("") { selectedTab = tab }
            .keyboardShortcut(KeyEquivalent(key), modifiers: [.command])
    }

    private func statsRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(TomatoPalette.secondaryText)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(TomatoPalette.primaryText)
                .monospacedDigit()
        }
        .font(.system(size: TomatoTypography.scaledSmall))
        .padding(.horizontal, 18)
        .frame(height: 54)
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: TomatoTypography.scaledSmall, weight: .semibold))
                .foregroundStyle(TomatoPalette.secondaryText)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 12, content: content)
                .font(.system(size: TomatoTypography.scaledSmall))
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .softCard(cornerRadius: 20)
        }
    }

    private func settingRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(TomatoPalette.secondaryText)
                .monospacedDigit()
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

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    private func changeSpeedRecordingSaveLocation() {
        let panel = NSOpenPanel()
        panel.title = "选择倍速录屏保存位置"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = speedRecordingDirectoryURL

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        SystemScreenRecordingService.setRecordingDirectoryURL(selectedURL)
        speedRecordingDirectoryURL = selectedURL
    }
}

struct TimerDesignPreview: View {
    @ObservedObject var idleViewModel: TimerViewModel
    @ObservedObject var runningViewModel: TimerViewModel

    var body: some View {
        ZStack(alignment: .top) {
            TomatoPalette.canvasGradient
                .ignoresSafeArea()

            PreviewMenuBar()

            HStack(alignment: .top, spacing: 90) {
                TimerMenuView(viewModel: idleViewModel)
                TimerMenuView(viewModel: runningViewModel)
            }
            .padding(.top, 74)
        }
        .frame(width: 1_448, height: 1_086)
    }
}

private struct PreviewMenuBar: View {
    var body: some View {
        HStack(spacing: 30) {
            Image(systemName: "apple.logo")
                .font(.system(size: 22, weight: .semibold))

            Group {
                Text("访达")
                Text("文件")
                Text("编辑")
                Text("显示")
                Text("前往")
                Text("窗口")
                Text("帮助")
            }
            .font(.system(size: TomatoTypography.small, weight: .medium))

            Spacer()

            Image("TomatoSteady")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)

            Image(systemName: "wifi")
                .font(.system(size: 18, weight: .medium))
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
            Image(systemName: "switch.2")
                .font(.system(size: 18, weight: .medium))
            Text("7月6日 周一 14:59")
                .font(.system(size: TomatoTypography.small, weight: .medium))
        }
        .foregroundStyle(TomatoPalette.primaryText.opacity(0.88))
        .padding(.horizontal, 32)
        .frame(height: 52)
        .background(.white.opacity(0.66))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.8))
                .frame(height: 1)
        }
        .shadow(color: TomatoPalette.shadow.opacity(0.08), radius: 14, y: 8)
    }
}

private enum TimerRingStyle {
    case ready
    case running
}

private struct TimerRing: View {
    let style: TimerRingStyle
    let mascotAssetName: String
    let time: String
    let durationFraction: Double

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let ringWidth = 14.0

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.88), TomatoPalette.ringInterior.opacity(0.94)],
                            center: UnitPoint(x: 0.42, y: 0.34),
                            startRadius: 8,
                            endRadius: size * 0.55
                        )
                    )
                    .shadow(color: TomatoPalette.shadow.opacity(0.10), radius: 18, y: 10)

                Circle()
                    .stroke(TomatoPalette.ringTrack, lineWidth: ringWidth)
                    .padding(ringWidth / 2)

                Circle()
                    .stroke(.white.opacity(0.74), lineWidth: 1)
                    .padding(ringWidth + 5)

                TickMarks()
                    .padding(24)

                Circle()
                    .trim(from: 0, to: min(max(durationFraction, 0), 1))
                    .stroke(
                        TomatoPalette.ringProgress,
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(ringWidth / 2)
                    .shadow(color: TomatoPalette.red.opacity(0.22), radius: 8, y: 4)

                Circle()
                    .stroke(TomatoPalette.border.opacity(0.7), lineWidth: 1)
                    .padding(1)

                if style == .ready {
                    FloatingMascot(assetName: mascotAssetName, height: size * 0.58)
                } else {
                    VStack(spacing: 10) {
                        FloatingMascot(assetName: mascotAssetName, height: size * 0.27)

                        Text(time)
                            .font(.system(size: TomatoTypography.scaledDisplay, weight: .medium, design: .rounded))
                            .foregroundStyle(TomatoPalette.primaryText)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .offset(y: 6)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(style == .ready ? "准备开始，\(time)" : "倒计时，\(time)")
    }
}

private struct TickMarks: View {
    var body: some View {
        GeometryReader { proxy in
            let radius = min(proxy.size.width, proxy.size.height) / 2 - 4

            ZStack {
                ForEach(0..<36, id: \.self) { index in
                    Capsule()
                        .fill(TomatoPalette.secondaryText.opacity(index.isMultiple(of: 3) ? 0.42 : 0.22))
                        .frame(width: 1.6, height: index.isMultiple(of: 3) ? 7 : 4)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(Double(index) * 10))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct FloatingMascot: View {
    let assetName: String
    let height: CGFloat
    @State private var floatsUp = false

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .offset(y: floatsUp ? -2 : 2)
            .animation(
                .easeInOut(duration: 2.6).repeatForever(autoreverses: true),
                value: floatsUp
            )
            .onAppear { floatsUp = true }
            .accessibilityHidden(true)
    }
}

private struct TimeSetupControls: View {
    @ObservedObject var viewModel: TimerViewModel

    var body: some View {
        HStack(spacing: 10) {
            smallButton("-5", hint: "减少五分钟") {
                viewModel.adjustPlannedFocusMinutes(by: -5)
            }
            .disabled(viewModel.plannedFocusMinutes <= 5)

            Button {
                viewModel.start()
            } label: {
                HStack(spacing: 13) {
                    Text("\(viewModel.plannedFocusMinutes)分钟")
                        .monospacedDigit()

                    Rectangle()
                        .fill(.white.opacity(0.38))
                        .frame(width: 1, height: 20)

                    Text("启动")
                        .fontWeight(.bold)
                }
                .font(.system(size: TomatoTypography.scaledSmall, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 68)
                .background(TomatoPalette.primaryGradient)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.42), lineWidth: 0.8)
                }
                .shadow(color: TomatoPalette.red.opacity(0.30), radius: 12, y: 7)
            }
            .buttonStyle(SoftPressButtonStyle())
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel("启动 \(viewModel.plannedFocusMinutes) 分钟专注")

            smallButton("+5", hint: "增加五分钟") {
                viewModel.adjustPlannedFocusMinutes(by: 5)
            }
            .disabled(viewModel.plannedFocusMinutes >= 60)
        }
    }

    private func smallButton(
        _ title: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: TomatoTypography.scaledSmall, weight: .semibold, design: .rounded))
                .foregroundStyle(TomatoPalette.primaryText)
                .frame(width: 48, height: 68)
                .softCard(cornerRadius: 19)
        }
        .buttonStyle(SoftPressButtonStyle())
        .accessibilityHint(hint)
    }
}

private struct RunningControls: View {
    @ObservedObject var viewModel: TimerViewModel

    var body: some View {
        HStack(spacing: 12) {
            secondaryControl(title: "重置", systemImage: "arrow.counterclockwise") {
                viewModel.reset()
            }
            .keyboardShortcut("r", modifiers: [.command])

            Button {
                viewModel.toggleRunning()
            } label: {
                Text(viewModel.status == .running ? "暂停" : "继续")
                    .font(.system(size: TomatoTypography.scaledHeading, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 68)
                    .background(TomatoPalette.primaryGradient)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.42), lineWidth: 0.8)
                    }
                    .shadow(color: TomatoPalette.red.opacity(0.31), radius: 13, y: 7)
            }
            .buttonStyle(SoftPressButtonStyle())
            .keyboardShortcut(.space, modifiers: [])

            secondaryControl(title: "跳过", systemImage: "forward.end.fill") {
                viewModel.skipPhase()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command])
        }
    }

    private func secondaryControl(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.system(size: TomatoTypography.scaledSmall, weight: .semibold))
            }
            .foregroundStyle(TomatoPalette.primaryText)
            .frame(width: 62, height: 68)
            .softCard(cornerRadius: 19)
        }
        .buttonStyle(SoftPressButtonStyle())
        .accessibilityLabel(title)
    }
}

private struct SoftPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .brightness(configuration.isPressed ? -0.025 : 0)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct GrainOverlay: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<90 {
                let x = CGFloat((index * 47) % 389) / 389 * size.width
                let y = CGFloat((index * 83) % 687) / 687 * size.height
                let diameter = CGFloat(index.isMultiple(of: 4) ? 1.4 : 0.8)
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)),
                    with: .color(index.isMultiple(of: 3) ? .white.opacity(0.30) : TomatoPalette.red.opacity(0.035))
                )
            }
        }
        .opacity(0.72)
    }
}

private enum TomatoPalette {
    static let red = Color(red: 0.953, green: 0.365, blue: 0.416)
    static let coral = Color(red: 0.957, green: 0.420, blue: 0.447)
    static let pink = Color(red: 0.969, green: 0.459, blue: 0.486)
    static let primaryText = Color(red: 0.125, green: 0.149, blue: 0.196)
    static let secondaryText = Color(red: 0.467, green: 0.451, blue: 0.478)
    static let border = Color(red: 0.47, green: 0.35, blue: 0.35).opacity(0.12)
    static let shadow = Color(red: 0.31, green: 0.19, blue: 0.20)
    static let panel = Color(red: 1.0, green: 0.980, blue: 0.965).opacity(0.94)
    static let segmentBackground = Color(red: 0.953, green: 0.925, blue: 0.918).opacity(0.88)
    static let ringTrack = Color(red: 1.0, green: 0.894, blue: 0.886).opacity(0.86)
    static let ringInterior = Color(red: 1.0, green: 0.969, blue: 0.953)

    static let primaryGradient = LinearGradient(
        colors: [Color(red: 0.973, green: 0.467, blue: 0.494), red],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let ringProgress = red

    static let canvasGradient = LinearGradient(
        colors: [
            Color(red: 0.973, green: 0.933, blue: 0.933),
            Color(red: 0.969, green: 0.953, blue: 0.937),
            Color(red: 1.0, green: 0.973, blue: 0.961)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private extension View {
    func softCard(cornerRadius: CGFloat) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.58))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.82), lineWidth: 0.8)
                }
                .shadow(color: TomatoPalette.shadow.opacity(0.09), radius: 9, y: 5)
        }
    }
}
