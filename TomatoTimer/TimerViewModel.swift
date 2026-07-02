import Combine
import Foundation

enum TimerPhase: Equatable {
    case focus
    case rest

    var next: TimerPhase {
        switch self {
        case .focus:
            return .rest
        case .rest:
            return .focus
        }
    }
}

enum TimerStatus: Equatable {
    case idle
    case running
    case paused
}

struct TimerSettings: Equatable {
    var focusMinutes: Int
    var breakMinutes: Int
    var notifyOnCompletion: Bool
    var recordSpeedVideo: Bool
    var recordingSpeed: ScreenRecordingSpeed
}

struct TimerStats: Equatable {
    var date: String
    var completedFocusSessionsToday: Int
    var focusedMinutesToday: Int
    var completedFocusSessionsTotal: Int
}

@MainActor
final class TimerViewModel: ObservableObject {
    @Published private(set) var remainingSeconds: Int
    @Published private(set) var phase: TimerPhase
    @Published private(set) var status: TimerStatus
    @Published private(set) var stats: TimerStats
    @Published private(set) var speedRecordingStatusMessage: String?

    @Published var focusMinutes: Int {
        didSet {
            defaults.set(Self.clamped(focusMinutes, range: 1...180), forKey: Self.focusMinutesKey)
            applyDurationChangeIfNeeded(for: .focus)
        }
    }

    @Published var breakMinutes: Int {
        didSet {
            defaults.set(Self.clamped(breakMinutes, range: 1...60), forKey: Self.breakMinutesKey)
            applyDurationChangeIfNeeded(for: .rest)
        }
    }

    @Published var notifyOnCompletion: Bool {
        didSet {
            defaults.set(notifyOnCompletion, forKey: Self.notifyOnCompletionKey)
            requestNotificationAuthorizationIfNeeded()
        }
    }

    @Published var recordSpeedVideo: Bool {
        didSet {
            defaults.set(recordSpeedVideo, forKey: Self.recordSpeedVideoKey)
            requestSpeedRecordingAuthorizationIfNeeded()
        }
    }

    @Published var recordingSpeed: ScreenRecordingSpeed {
        didSet {
            defaults.set(recordingSpeed.rawValue, forKey: Self.recordingSpeedKey)
        }
    }

    private static let focusMinutesKey = "focusMinutes"
    private static let breakMinutesKey = "breakMinutes"
    private static let notifyOnCompletionKey = "notifyOnCompletion"
    private static let recordSpeedVideoKey = "recordSpeedVideo"
    private static let recordingSpeedKey = "recordingSpeed"
    private static let statsDateKey = "statsDate"
    private static let completedFocusSessionsTodayKey = "completedFocusSessionsToday"
    private static let focusedMinutesTodayKey = "focusedMinutesToday"
    private static let completedFocusSessionsTotalKey = "completedFocusSessionsTotal"

    private let defaults: UserDefaults
    private let notificationService: NotificationService
    private let screenRecordingService: ScreenRecordingService
    private let currentDateProvider: () -> Date
    private var timer: Timer?
    private var isSpeedRecordingSessionActive = false
    private var isSpeedRecordingPaused = false

    init(
        defaults: UserDefaults = .standard,
        notificationService: NotificationService,
        screenRecordingService: ScreenRecordingService = SystemScreenRecordingService(),
        currentDateProvider: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.notificationService = notificationService
        self.screenRecordingService = screenRecordingService
        self.currentDateProvider = currentDateProvider

        let savedFocusMinutes = defaults.integer(forKey: Self.focusMinutesKey)
        let savedBreakMinutes = defaults.integer(forKey: Self.breakMinutesKey)
        let focus = savedFocusMinutes == 0 ? 25 : Self.clamped(savedFocusMinutes, range: 1...180)
        let rest = savedBreakMinutes == 0 ? 5 : Self.clamped(savedBreakMinutes, range: 1...60)
        let notifyOnCompletion = defaults.object(forKey: Self.notifyOnCompletionKey) as? Bool ?? true
        let recordSpeedVideo = defaults.object(forKey: Self.recordSpeedVideoKey) as? Bool ?? false
        let recordingSpeed = ScreenRecordingSpeed(
            rawValue: defaults.integer(forKey: Self.recordingSpeedKey)
        ) ?? .ten
        let today = Self.dateString(for: currentDateProvider())
        let savedStatsDate = defaults.string(forKey: Self.statsDateKey) ?? today
        let savedTotal = defaults.integer(forKey: Self.completedFocusSessionsTotalKey)
        let savedTodaySessions = defaults.integer(forKey: Self.completedFocusSessionsTodayKey)
        let savedTodayMinutes = defaults.integer(forKey: Self.focusedMinutesTodayKey)

        self.focusMinutes = focus
        self.breakMinutes = rest
        self.notifyOnCompletion = notifyOnCompletion
        self.recordSpeedVideo = recordSpeedVideo
        self.recordingSpeed = recordingSpeed
        self.stats = TimerStats(
            date: today,
            completedFocusSessionsToday: savedStatsDate == today ? savedTodaySessions : 0,
            focusedMinutesToday: savedStatsDate == today ? savedTodayMinutes : 0,
            completedFocusSessionsTotal: savedTotal
        )
        self.phase = .focus
        self.status = .idle
        self.remainingSeconds = focus * 60
        self.speedRecordingStatusMessage = nil
        persistStats()
    }

    deinit {
        MainActor.assumeIsolated {
            timer?.invalidate()
            screenRecordingService.discardRecording()
        }
    }

    var settings: TimerSettings {
        TimerSettings(
            focusMinutes: focusMinutes,
            breakMinutes: breakMinutes,
            notifyOnCompletion: notifyOnCompletion,
            recordSpeedVideo: recordSpeedVideo,
            recordingSpeed: recordingSpeed
        )
    }

    var canChangeSpeedRecordingSetting: Bool {
        status == .idle
    }

    var progress: Double {
        let total = Double(totalSeconds(for: phase))
        guard total > 0 else { return 0 }
        return 1 - (Double(remainingSeconds) / total)
    }

    var formattedRemainingTime: String {
        Self.format(seconds: remainingSeconds)
    }

    var menuBarTitle: String? {
        guard status != .idle else { return nil }

        switch phase {
        case .focus:
            return formattedRemainingTime
        case .rest:
            return "休息 \(formattedRemainingTime)"
        }
    }

    var phaseTitle: String {
        if status == .paused {
            return "已暂停"
        }

        switch phase {
        case .focus:
            return status == .running ? "专注中" : "准备专注"
        case .rest:
            return status == .running ? "休息中" : "准备休息"
        }
    }

    var primaryButtonTitle: String {
        switch status {
        case .idle:
            return "开始"
        case .running:
            return "暂停"
        case .paused:
            return "继续"
        }
    }

    func start() {
        guard status != .running else { return }
        requestNotificationAuthorizationIfNeeded()
        status = .running
        startOrResumeSpeedRecordingIfNeeded()
        startTimer()
    }

    func pause() {
        guard status == .running else { return }
        status = .paused
        pauseSpeedRecordingIfNeeded()
        stopTimer()
    }

    func toggleRunning() {
        status == .running ? pause() : start()
    }

    func reset() {
        stopTimer()
        discardSpeedRecordingIfNeeded()
        status = .idle
        phase = .focus
        remainingSeconds = totalSeconds(for: .focus)
    }

    func skipPhase() {
        discardSpeedRecordingIfNeeded()
        transitionToNextPhase(sendNotification: false)
    }

    func tick() {
        guard status == .running else { return }

        if remainingSeconds > 1 {
            remainingSeconds -= 1
        } else {
            finishSpeedRecordingIfNeeded()
            recordCompletedFocusSessionIfNeeded()
            transitionToNextPhase(sendNotification: true)
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func transitionToNextPhase(sendNotification: Bool) {
        let nextPhase = phase.next
        phase = nextPhase
        remainingSeconds = totalSeconds(for: nextPhase)

        if sendNotification, notifyOnCompletion {
            notificationService.sendPhaseFinishedNotification(nextPhase: nextPhase)
        }

        if status == .running {
            startOrResumeSpeedRecordingIfNeeded()
            startTimer()
        }
    }

    private func requestNotificationAuthorizationIfNeeded() {
        guard notifyOnCompletion else { return }
        notificationService.requestAuthorizationIfNeeded()
    }

    private func startOrResumeSpeedRecordingIfNeeded() {
        guard recordSpeedVideo, phase == .focus else { return }

        if isSpeedRecordingSessionActive {
            isSpeedRecordingPaused = false
            speedRecordingStatusMessage = "正在恢复倍速录屏"
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.screenRecordingService.resumeRecording()
                    await MainActor.run {
                        guard self.isSpeedRecordingSessionActive else { return }
                        self.speedRecordingStatusMessage = "倍速录屏中"
                    }
                } catch {
                    await MainActor.run {
                        self.speedRecordingStatusMessage = error.localizedDescription
                    }
                }
            }
            return
        }

        isSpeedRecordingSessionActive = true
        isSpeedRecordingPaused = false
        speedRecordingStatusMessage = "正在准备倍速录屏"
        let sessionRecordingSpeed = recordingSpeed

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.screenRecordingService.startRecordingFocusSession(speed: sessionRecordingSpeed)
                await MainActor.run {
                    guard self.isSpeedRecordingSessionActive else { return }
                    self.speedRecordingStatusMessage = "倍速录屏中"
                }
            } catch {
                await MainActor.run {
                    self.isSpeedRecordingSessionActive = false
                    self.isSpeedRecordingPaused = false
                    self.speedRecordingStatusMessage = error.localizedDescription
                }
            }
        }
    }

    private func requestSpeedRecordingAuthorizationIfNeeded() {
        guard recordSpeedVideo else {
            speedRecordingStatusMessage = nil
            return
        }

        guard status == .idle else { return }

        if screenRecordingService.requestAuthorizationIfNeeded() {
            speedRecordingStatusMessage = nil
        } else {
            speedRecordingStatusMessage = ScreenRecordingError.screenCapturePermissionDenied.localizedDescription
        }
    }

    private func pauseSpeedRecordingIfNeeded() {
        guard isSpeedRecordingSessionActive, phase == .focus else { return }
        screenRecordingService.pauseRecording()
        isSpeedRecordingPaused = true
        speedRecordingStatusMessage = "倍速录屏已暂停"
    }

    private func finishSpeedRecordingIfNeeded() {
        guard isSpeedRecordingSessionActive, phase == .focus else { return }

        isSpeedRecordingSessionActive = false
        isSpeedRecordingPaused = false
        speedRecordingStatusMessage = "正在保存倍速录屏"

        Task { [weak self] in
            guard let self else { return }
            do {
                let outputURL = try await self.screenRecordingService.finishAndSaveRecording()
                await MainActor.run {
                    if outputURL != nil {
                        self.speedRecordingStatusMessage = "倍速录屏已保存"
                    } else {
                        self.speedRecordingStatusMessage = nil
                    }
                }
            } catch {
                await MainActor.run {
                    self.speedRecordingStatusMessage = error.localizedDescription
                }
            }
        }
    }

    private func discardSpeedRecordingIfNeeded() {
        guard isSpeedRecordingSessionActive else { return }
        screenRecordingService.discardRecording()
        isSpeedRecordingSessionActive = false
        isSpeedRecordingPaused = false
        speedRecordingStatusMessage = nil
    }

    private func applyDurationChangeIfNeeded(for changedPhase: TimerPhase) {
        guard phase == changedPhase, status != .running else { return }
        remainingSeconds = totalSeconds(for: changedPhase)
    }

    private func recordCompletedFocusSessionIfNeeded() {
        guard phase == .focus else { return }

        refreshTodayStatsIfNeeded()
        stats.completedFocusSessionsToday += 1
        stats.focusedMinutesToday += Self.clamped(focusMinutes, range: 1...180)
        stats.completedFocusSessionsTotal += 1
        persistStats()
    }

    private func refreshTodayStatsIfNeeded() {
        let today = Self.dateString(for: currentDateProvider())
        guard stats.date != today else { return }

        stats = TimerStats(
            date: today,
            completedFocusSessionsToday: 0,
            focusedMinutesToday: 0,
            completedFocusSessionsTotal: stats.completedFocusSessionsTotal
        )
        persistStats()
    }

    private func persistStats() {
        defaults.set(stats.date, forKey: Self.statsDateKey)
        defaults.set(stats.completedFocusSessionsToday, forKey: Self.completedFocusSessionsTodayKey)
        defaults.set(stats.focusedMinutesToday, forKey: Self.focusedMinutesTodayKey)
        defaults.set(stats.completedFocusSessionsTotal, forKey: Self.completedFocusSessionsTotalKey)
    }

    private func totalSeconds(for phase: TimerPhase) -> Int {
        switch phase {
        case .focus:
            return Self.clamped(focusMinutes, range: 1...180) * 60
        case .rest:
            return Self.clamped(breakMinutes, range: 1...60) * 60
        }
    }

    private static func format(seconds: Int) -> String {
        let minutes = seconds / 60
        let seconds = seconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private static func clamped(_ value: Int, range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func dateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
