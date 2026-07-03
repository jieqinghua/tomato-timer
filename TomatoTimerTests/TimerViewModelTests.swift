import AppKit
import SwiftUI
import XCTest
@testable import TomatoTimer

@MainActor
final class TimerViewModelTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!
    private var notificationService: MockNotificationService!
    private var screenRecordingService: MockScreenRecordingService!
    private var viewModel: TimerViewModel!
    private var currentDate: Date!

    override func setUp() async throws {
        defaultsSuiteName = "TimerViewModelTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        notificationService = MockNotificationService()
        screenRecordingService = MockScreenRecordingService()
        currentDate = Self.makeDate(year: 2026, month: 5, day: 28)
        viewModel = TimerViewModel(
            defaults: defaults,
            notificationService: notificationService,
            screenRecordingService: screenRecordingService,
            currentDateProvider: { self.currentDate }
        )
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        viewModel = nil
        notificationService = nil
        screenRecordingService = nil
        defaults = nil
        defaultsSuiteName = nil
        currentDate = nil
    }

    func testInitialStateUsesDefaultFocusRecommendation() {
        XCTAssertEqual(viewModel.status, .idle)
        XCTAssertEqual(viewModel.phase, .focus)
        XCTAssertEqual(viewModel.selectedFocusMood, .steady)
        XCTAssertEqual(viewModel.plannedFocusMinutes, 15)
        XCTAssertTrue(viewModel.isUsingRecommendedFocusDuration)
        XCTAssertEqual(viewModel.remainingSeconds, 15 * 60)
        XCTAssertEqual(viewModel.primaryButtonTitle, "开始专注 15 分钟")
        XCTAssertNil(viewModel.menuBarTitle)
        XCTAssertEqual(
            viewModel.settings,
            TimerSettings(
                focusMinutes: 25,
                breakMinutes: 5,
                autoStartFocusAfterBreak: true,
                notifyOnCompletion: true,
                recordSpeedVideo: false,
                recordingSpeed: .ten
            )
        )
        XCTAssertEqual(
            viewModel.stats,
            TimerStats(
                date: "2026-05-28",
                completedFocusSessionsToday: 0,
                focusedMinutesToday: 0,
                completedFocusSessionsTotal: 0
            )
        )
    }

    func testFocusMoodRecommendationsMatchProductPlan() {
        XCTAssertEqual(FocusMood.tired.title, "有点累")
        XCTAssertEqual(FocusMood.tired.recommendedMinutes, 5)
        XCTAssertEqual(FocusMood.steady.title, "还可以")
        XCTAssertEqual(FocusMood.steady.recommendedMinutes, 15)
        XCTAssertEqual(FocusMood.energetic.title, "状态不错")
        XCTAssertEqual(FocusMood.energetic.recommendedMinutes, 30)
    }

    func testSelectingMoodUpdatesThisSessionWithoutChangingSavedDuration() {
        XCTAssertEqual(viewModel.focusMinutes, 25)

        viewModel.selectFocusMood(.tired)

        XCTAssertEqual(viewModel.selectedFocusMood, .tired)
        XCTAssertEqual(viewModel.plannedFocusMinutes, 5)
        XCTAssertEqual(viewModel.remainingSeconds, 5 * 60)
        XCTAssertTrue(viewModel.isUsingRecommendedFocusDuration)
        XCTAssertEqual(viewModel.focusMinutes, 25)

        viewModel.selectFocusMood(.energetic)

        XCTAssertEqual(viewModel.plannedFocusMinutes, 30)
        XCTAssertEqual(viewModel.remainingSeconds, 30 * 60)
        XCTAssertEqual(viewModel.focusMinutes, 25)
    }

    func testCustomDurationOverridesRecommendationAndPersists() {
        viewModel.focusMinutes = 12

        XCTAssertEqual(viewModel.plannedFocusMinutes, 12)
        XCTAssertEqual(viewModel.remainingSeconds, 12 * 60)
        XCTAssertFalse(viewModel.isUsingRecommendedFocusDuration)

        let reloadedViewModel = TimerViewModel(
            defaults: defaults,
            notificationService: notificationService,
            screenRecordingService: screenRecordingService,
            currentDateProvider: { self.currentDate }
        )

        XCTAssertEqual(reloadedViewModel.settings.focusMinutes, 12)
        XCTAssertEqual(reloadedViewModel.plannedFocusMinutes, 15)
        XCTAssertTrue(reloadedViewModel.isUsingRecommendedFocusDuration)
    }

    func testStartChangesStatusAndRequestsNotifications() {
        viewModel.start()

        XCTAssertEqual(viewModel.status, .running)
        XCTAssertEqual(notificationService.authorizationRequestCount, 1)
        XCTAssertEqual(viewModel.menuBarTitle, "15:00")
    }

    func testPausePreservesRemainingTime() {
        viewModel.start()
        viewModel.tick()
        let remaining = viewModel.remainingSeconds

        viewModel.pause()

        XCTAssertEqual(viewModel.status, .paused)
        XCTAssertEqual(viewModel.remainingSeconds, remaining)
        XCTAssertEqual(viewModel.menuBarTitle, "14:59")
        XCTAssertEqual(viewModel.primaryButtonTitle, "继续")
    }

    func testSupportMessageFollowsFocusAndRestStateWithoutPressureLanguage() {
        XCTAssertEqual(viewModel.supportMessage, "先把这一小段守住")

        viewModel.selectFocusMood(.tired)
        XCTAssertEqual(viewModel.supportMessage, "不求做完，先往前一点")

        viewModel.start()
        XCTAssertEqual(viewModel.supportMessage, "已经开始了，先守住这一小段")

        viewModel.pause()
        XCTAssertEqual(viewModel.supportMessage, "停一下也没关系，准备好再继续")

        viewModel.skipPhase()
        XCTAssertEqual(viewModel.supportMessage, "休息一会儿，准备好再继续")

        viewModel.start()
        XCTAssertEqual(viewModel.supportMessage, "离开屏幕，轻轻松一会儿")

        for message in [
            FocusMood.tired.encouragement,
            FocusMood.steady.encouragement,
            FocusMood.energetic.encouragement,
            viewModel.supportMessage
        ] {
            XCTAssertFalse(message.contains("失败"))
            XCTAssertFalse(message.contains("偷懒"))
            XCTAssertFalse(message.contains("放弃"))
        }
    }

    func testResetReturnsToDefaultFocusRecommendation() {
        viewModel.focusMinutes = 30
        viewModel.start()
        viewModel.tick()

        viewModel.reset()

        XCTAssertEqual(viewModel.status, .idle)
        XCTAssertEqual(viewModel.phase, .focus)
        XCTAssertEqual(viewModel.selectedFocusMood, .steady)
        XCTAssertEqual(viewModel.plannedFocusMinutes, 15)
        XCTAssertEqual(viewModel.remainingSeconds, 15 * 60)
        XCTAssertTrue(viewModel.isUsingRecommendedFocusDuration)
        XCTAssertNil(viewModel.menuBarTitle)
    }

    func testSkipSwitchesBetweenFocusAndBreak() {
        viewModel.focusMinutes = 2
        viewModel.breakMinutes = 1

        viewModel.skipPhase()
        XCTAssertEqual(viewModel.phase, .rest)
        XCTAssertEqual(viewModel.remainingSeconds, 60)

        viewModel.skipPhase()
        XCTAssertEqual(viewModel.phase, .focus)
        XCTAssertEqual(viewModel.status, .idle)
        XCTAssertEqual(viewModel.selectedFocusMood, .steady)
        XCTAssertEqual(viewModel.remainingSeconds, 15 * 60)
    }

    func testCountdownReachingZeroSwitchesPhaseAndSendsNotification() {
        viewModel.focusMinutes = 1
        viewModel.breakMinutes = 1
        viewModel.start()

        for _ in 0..<60 {
            viewModel.tick()
        }

        XCTAssertEqual(viewModel.status, .running)
        XCTAssertEqual(viewModel.phase, .rest)
        XCTAssertEqual(viewModel.remainingSeconds, 60)
        XCTAssertEqual(viewModel.menuBarTitle, "休息 01:00")
        XCTAssertEqual(notificationService.nextPhases, [.rest])
    }

    func testStartDoesNotRequestNotificationsWhenCompletionNotificationsAreDisabled() {
        viewModel.notifyOnCompletion = false

        viewModel.start()

        XCTAssertEqual(viewModel.status, .running)
        XCTAssertEqual(notificationService.authorizationRequestCount, 0)
    }

    func testEnablingNotificationSettingRequestsAuthorization() {
        viewModel.notifyOnCompletion = false

        viewModel.notifyOnCompletion = true

        XCTAssertEqual(notificationService.authorizationRequestCount, 1)
    }

    func testCountdownReachingZeroDoesNotNotifyWhenCompletionNotificationsAreDisabled() {
        viewModel.focusMinutes = 1
        viewModel.breakMinutes = 1
        viewModel.notifyOnCompletion = false
        viewModel.start()

        for _ in 0..<60 {
            viewModel.tick()
        }

        XCTAssertEqual(viewModel.status, .running)
        XCTAssertEqual(viewModel.phase, .rest)
        XCTAssertEqual(notificationService.nextPhases, [])
    }

    func testNotificationSettingPersists() {
        viewModel.notifyOnCompletion = false

        let reloadedViewModel = TimerViewModel(
            defaults: defaults,
            notificationService: notificationService,
            screenRecordingService: screenRecordingService,
            currentDateProvider: { self.currentDate }
        )

        XCTAssertFalse(reloadedViewModel.notifyOnCompletion)
    }

    func testAutoStartFocusAfterBreakDefaultsToEnabledAndPersists() {
        XCTAssertTrue(viewModel.autoStartFocusAfterBreak)

        viewModel.autoStartFocusAfterBreak = false

        let reloadedViewModel = TimerViewModel(
            defaults: defaults,
            notificationService: notificationService,
            screenRecordingService: screenRecordingService,
            currentDateProvider: { self.currentDate }
        )

        XCTAssertFalse(reloadedViewModel.autoStartFocusAfterBreak)
    }

    func testSpeedRecordingSettingPersists() {
        viewModel.recordSpeedVideo = true

        let reloadedViewModel = TimerViewModel(
            defaults: defaults,
            notificationService: notificationService,
            screenRecordingService: screenRecordingService,
            currentDateProvider: { self.currentDate }
        )

        XCTAssertTrue(reloadedViewModel.recordSpeedVideo)
    }

    func testSpeedRecordingDefaultsToTenTimes() {
        XCTAssertEqual(viewModel.recordingSpeed, .ten)
    }

    func testSpeedRecordingSpeedPersists() {
        viewModel.recordingSpeed = .twenty

        let reloadedViewModel = TimerViewModel(
            defaults: defaults,
            notificationService: notificationService,
            screenRecordingService: screenRecordingService,
            currentDateProvider: { self.currentDate }
        )

        XCTAssertEqual(reloadedViewModel.recordingSpeed, .twenty)
    }

    func testSpeedRecordingOptionTitlesAndStorageEstimates() {
        XCTAssertEqual(ScreenRecordingSpeed.five.shortTitle, "5x")
        XCTAssertEqual(ScreenRecordingSpeed.ten.shortTitle, "10x")
        XCTAssertEqual(ScreenRecordingSpeed.twenty.shortTitle, "20x")
        XCTAssertEqual(ScreenRecordingSpeed.five.storageEstimateTitle, "约 120M/30分钟")
        XCTAssertEqual(ScreenRecordingSpeed.ten.storageEstimateTitle, "约60M/30分钟")
        XCTAssertEqual(ScreenRecordingSpeed.twenty.storageEstimateTitle, "约30M/30分钟")
    }

    func testSpeedRecordingSettingsCanOnlyChangeWhileIdle() {
        XCTAssertTrue(viewModel.canChangeSpeedRecordingSetting)

        viewModel.start()
        XCTAssertFalse(viewModel.canChangeSpeedRecordingSetting)

        viewModel.pause()
        XCTAssertFalse(viewModel.canChangeSpeedRecordingSetting)

        viewModel.reset()
        XCTAssertTrue(viewModel.canChangeSpeedRecordingSetting)
    }

    func testDurationsCanOnlyChangeInReadyFocusState() {
        XCTAssertTrue(viewModel.canAdjustDurations)

        viewModel.start()
        XCTAssertFalse(viewModel.canAdjustDurations)

        viewModel.pause()
        XCTAssertFalse(viewModel.canAdjustDurations)

        viewModel.reset()
        XCTAssertTrue(viewModel.canAdjustDurations)

        viewModel.skipPhase()
        XCTAssertFalse(viewModel.canAdjustDurations)
    }

    func testBreakDurationCanOnlyChangeWhileTimerIsIdle() {
        XCTAssertTrue(viewModel.canAdjustBreakDuration)

        viewModel.start()
        XCTAssertFalse(viewModel.canAdjustBreakDuration)

        viewModel.pause()
        XCTAssertFalse(viewModel.canAdjustBreakDuration)

        viewModel.reset()
        viewModel.skipPhase()
        XCTAssertTrue(viewModel.canAdjustBreakDuration)
    }

    func testDefaultSpeedRecordingDirectoryUsesMoviesTomatoTimerFolder() throws {
        SystemScreenRecordingService.resetRecordingDirectoryURL(defaults: defaults)

        let directory = try SystemScreenRecordingService.recordingDirectoryURL(defaults: defaults)

        XCTAssertEqual(directory.lastPathComponent, "Tomato Timer")
        XCTAssertEqual(directory.deletingLastPathComponent().lastPathComponent, "Movies")
    }

    func testCustomSpeedRecordingDirectoryPersists() throws {
        let customDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TomatoTimerCustomRecording", isDirectory: true)

        SystemScreenRecordingService.setRecordingDirectoryURL(customDirectory, defaults: defaults)

        XCTAssertEqual(
            try SystemScreenRecordingService.recordingDirectoryURL(defaults: defaults),
            customDirectory
        )
    }

    func testCanceledSpeedRecordingDirectorySelectionDoesNotOverwriteExistingDirectory() throws {
        let existingDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TomatoTimerExistingRecording", isDirectory: true)
        SystemScreenRecordingService.setRecordingDirectoryURL(existingDirectory, defaults: defaults)

        XCTAssertEqual(
            try SystemScreenRecordingService.recordingDirectoryURL(defaults: defaults),
            existingDirectory
        )
    }

    func testEnablingSpeedRecordingRequestsAuthorization() {
        viewModel.recordSpeedVideo = true

        XCTAssertEqual(screenRecordingService.authorizationRequestCount, 1)
    }

    func testDeniedSpeedRecordingAuthorizationShowsMessage() {
        screenRecordingService.authorizationResult = false

        viewModel.recordSpeedVideo = true

        XCTAssertEqual(viewModel.speedRecordingStatusMessage, "请在系统设置中允许屏幕录制后重启应用")
    }

    func testStartBeginsSpeedRecordingForFocusWhenEnabled() async {
        viewModel.recordSpeedVideo = true

        viewModel.start()
        await waitForAsyncWork()

        XCTAssertEqual(screenRecordingService.startCount, 1)
        XCTAssertEqual(screenRecordingService.startedSpeeds, [.ten])
        XCTAssertEqual(screenRecordingService.resumeCount, 0)
        XCTAssertEqual(viewModel.speedRecordingStatusMessage, "倍速录屏中")
    }

    func testSelectedSpeedIsPassedWhenSpeedRecordingStarts() async {
        viewModel.recordingSpeed = .five
        viewModel.recordSpeedVideo = true

        viewModel.start()
        await waitForAsyncWork()

        XCTAssertEqual(screenRecordingService.startedSpeeds, [.five])
    }

    func testPausePausesSpeedRecordingAndStartResumesIt() async {
        viewModel.recordSpeedVideo = true
        viewModel.start()
        await waitForAsyncWork()

        viewModel.pause()
        viewModel.start()
        await waitForAsyncWork()

        XCTAssertEqual(screenRecordingService.pauseCount, 1)
        XCTAssertEqual(screenRecordingService.resumeCount, 1)
        XCTAssertEqual(viewModel.speedRecordingStatusMessage, "倍速录屏中")
    }

    func testSpeedRecordingResumeFailureDoesNotBlockTimer() async {
        screenRecordingService.resumeError = ScreenRecordingError.recordingUnavailable
        viewModel.recordSpeedVideo = true
        viewModel.start()
        await waitForAsyncWork()

        viewModel.pause()
        viewModel.start()
        await waitForAsyncWork()

        XCTAssertEqual(viewModel.status, .running)
        XCTAssertEqual(screenRecordingService.resumeCount, 1)
        XCTAssertEqual(viewModel.speedRecordingStatusMessage, "需要授权屏幕录制")
    }

    func testCompletedFocusSessionSavesSpeedRecording() async {
        viewModel.focusMinutes = 1
        viewModel.breakMinutes = 1
        viewModel.recordSpeedVideo = true
        viewModel.start()
        await waitForAsyncWork()

        completeCurrentMinute()
        await waitForAsyncWork()

        XCTAssertEqual(screenRecordingService.finishCount, 1)
        XCTAssertEqual(screenRecordingService.discardCount, 0)
        XCTAssertEqual(viewModel.phase, .rest)
        XCTAssertEqual(viewModel.speedRecordingStatusMessage, "倍速录屏已保存")
    }

    func testCompletedBreakReturnsToReadyWithoutStartingAnotherRecording() async {
        viewModel.focusMinutes = 1
        viewModel.breakMinutes = 1
        viewModel.autoStartFocusAfterBreak = false
        viewModel.recordSpeedVideo = true
        viewModel.start()
        await waitForAsyncWork()

        completeCurrentMinute()
        await waitForAsyncWork()
        completeCurrentMinute()
        await waitForAsyncWork()

        XCTAssertEqual(viewModel.phase, .focus)
        XCTAssertEqual(viewModel.status, .idle)
        XCTAssertEqual(viewModel.selectedFocusMood, .steady)
        XCTAssertEqual(viewModel.plannedFocusMinutes, 15)
        XCTAssertEqual(viewModel.remainingSeconds, 15 * 60)
        XCTAssertEqual(screenRecordingService.finishCount, 1)
        XCTAssertEqual(screenRecordingService.startCount, 1)
        XCTAssertEqual(viewModel.speedRecordingStatusMessage, "倍速录屏已保存")
    }

    func testCompletedBreakAutoStartsNextFocusAndRecordingByDefault() async {
        viewModel.focusMinutes = 1
        viewModel.breakMinutes = 1
        viewModel.recordSpeedVideo = true
        viewModel.start()
        await waitForAsyncWork()

        completeCurrentMinute()
        await waitForAsyncWork()
        completeCurrentMinute()
        await waitForAsyncWork()

        XCTAssertEqual(viewModel.phase, .focus)
        XCTAssertEqual(viewModel.status, .running)
        XCTAssertEqual(viewModel.selectedFocusMood, .steady)
        XCTAssertEqual(viewModel.plannedFocusMinutes, 15)
        XCTAssertEqual(viewModel.remainingSeconds, 15 * 60)
        XCTAssertEqual(screenRecordingService.finishCount, 1)
        XCTAssertEqual(screenRecordingService.startCount, 2)
        XCTAssertEqual(viewModel.speedRecordingStatusMessage, "倍速录屏中")
    }

    func testSpeedRecordingFinishFailureShowsErrorMessage() async {
        screenRecordingService.finishError = ScreenRecordingError.writingFailed("writer append failed")
        viewModel.focusMinutes = 1
        viewModel.breakMinutes = 1
        viewModel.recordSpeedVideo = true
        viewModel.start()
        await waitForAsyncWork()

        completeCurrentMinute()
        await waitForAsyncWork()

        XCTAssertEqual(screenRecordingService.finishCount, 1)
        XCTAssertEqual(viewModel.phase, .rest)
        XCTAssertEqual(viewModel.speedRecordingStatusMessage, "录屏失败：writer append failed")
    }

    func testSkipFocusDiscardsSpeedRecording() async {
        viewModel.recordSpeedVideo = true
        viewModel.start()
        await waitForAsyncWork()

        viewModel.skipPhase()

        XCTAssertEqual(screenRecordingService.discardCount, 1)
        XCTAssertEqual(screenRecordingService.finishCount, 0)
        XCTAssertEqual(viewModel.phase, .rest)
        XCTAssertNil(viewModel.speedRecordingStatusMessage)
    }

    func testResetDiscardsSpeedRecording() async {
        viewModel.recordSpeedVideo = true
        viewModel.start()
        await waitForAsyncWork()

        viewModel.reset()

        XCTAssertEqual(screenRecordingService.discardCount, 1)
        XCTAssertEqual(screenRecordingService.finishCount, 0)
        XCTAssertEqual(viewModel.status, .idle)
        XCTAssertNil(viewModel.speedRecordingStatusMessage)
    }

    func testRestPhaseDoesNotStartSpeedRecording() async {
        viewModel.recordSpeedVideo = true
        viewModel.skipPhase()

        viewModel.start()
        await waitForAsyncWork()

        XCTAssertEqual(screenRecordingService.startCount, 0)
        XCTAssertNil(viewModel.speedRecordingStatusMessage)
    }

    func testSpeedRecordingFailureDoesNotBlockTimer() async {
        screenRecordingService.startError = ScreenRecordingError.recordingUnavailable
        viewModel.recordSpeedVideo = true

        viewModel.start()
        await waitForAsyncWork()

        XCTAssertEqual(viewModel.status, .running)
        XCTAssertEqual(screenRecordingService.startCount, 1)
        XCTAssertEqual(viewModel.speedRecordingStatusMessage, "需要授权屏幕录制")
    }

    func testCompletedFocusSessionUpdatesStats() {
        viewModel.focusMinutes = 1
        viewModel.breakMinutes = 1
        viewModel.start()

        completeCurrentMinute()

        XCTAssertEqual(
            viewModel.stats,
            TimerStats(
                date: "2026-05-28",
                completedFocusSessionsToday: 1,
                focusedMinutesToday: 1,
                completedFocusSessionsTotal: 1
            )
        )
    }

    func testSkipFocusDoesNotUpdateStats() {
        viewModel.focusMinutes = 1

        viewModel.skipPhase()

        XCTAssertEqual(viewModel.phase, .rest)
        XCTAssertEqual(viewModel.stats.completedFocusSessionsToday, 0)
        XCTAssertEqual(viewModel.stats.focusedMinutesToday, 0)
        XCTAssertEqual(viewModel.stats.completedFocusSessionsTotal, 0)
    }

    func testResetDoesNotUpdateStats() {
        viewModel.focusMinutes = 1
        viewModel.start()
        viewModel.tick()

        viewModel.reset()

        XCTAssertEqual(viewModel.stats.completedFocusSessionsToday, 0)
        XCTAssertEqual(viewModel.stats.focusedMinutesToday, 0)
        XCTAssertEqual(viewModel.stats.completedFocusSessionsTotal, 0)
    }

    func testCompletedBreakDoesNotUpdateStats() {
        viewModel.focusMinutes = 1
        viewModel.breakMinutes = 1
        viewModel.skipPhase()
        viewModel.start()

        completeCurrentMinute()

        XCTAssertEqual(viewModel.phase, .focus)
        XCTAssertEqual(viewModel.status, .running)
        XCTAssertEqual(viewModel.plannedFocusMinutes, 15)
        XCTAssertEqual(viewModel.stats.completedFocusSessionsToday, 0)
        XCTAssertEqual(viewModel.stats.focusedMinutesToday, 0)
        XCTAssertEqual(viewModel.stats.completedFocusSessionsTotal, 0)
    }

    func testStatsPersist() {
        viewModel.focusMinutes = 1
        viewModel.breakMinutes = 1
        viewModel.start()
        completeCurrentMinute()

        let reloadedViewModel = TimerViewModel(
            defaults: defaults,
            notificationService: notificationService,
            screenRecordingService: screenRecordingService,
            currentDateProvider: { self.currentDate }
        )

        XCTAssertEqual(
            reloadedViewModel.stats,
            TimerStats(
                date: "2026-05-28",
                completedFocusSessionsToday: 1,
                focusedMinutesToday: 1,
                completedFocusSessionsTotal: 1
            )
        )
    }

    func testOldDailyStatsResetButTotalPersists() {
        defaults.set("2026-05-27", forKey: "statsDate")
        defaults.set(4, forKey: "completedFocusSessionsToday")
        defaults.set(100, forKey: "focusedMinutesToday")
        defaults.set(9, forKey: "completedFocusSessionsTotal")

        let reloadedViewModel = TimerViewModel(
            defaults: defaults,
            notificationService: notificationService,
            screenRecordingService: screenRecordingService,
            currentDateProvider: { self.currentDate }
        )

        XCTAssertEqual(
            reloadedViewModel.stats,
            TimerStats(
                date: "2026-05-28",
                completedFocusSessionsToday: 0,
                focusedMinutesToday: 0,
                completedFocusSessionsTotal: 9
            )
        )
    }

    func testStatsRefreshWhenAppRunsAcrossMidnight() {
        viewModel.focusMinutes = 1
        viewModel.breakMinutes = 1
        viewModel.start()
        completeCurrentMinute()
        currentDate = Self.makeDate(year: 2026, month: 5, day: 29)
        viewModel.skipPhase()
        viewModel.focusMinutes = 1
        viewModel.start()

        completeCurrentMinute()

        XCTAssertEqual(
            viewModel.stats,
            TimerStats(
                date: "2026-05-29",
                completedFocusSessionsToday: 1,
                focusedMinutesToday: 1,
                completedFocusSessionsTotal: 2
            )
        )
    }

    func testTabsRenderForVisualQA() throws {
        let hostingView = NSHostingView(rootView: TimerMenuView(viewModel: viewModel))
        hostingView.appearance = NSAppearance(named: .aqua)
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 500)
        hostingView.layoutSubtreeIfNeeded()

        try writeSnapshot(of: hostingView, named: "focus")

        guard let tabControl: NSSegmentedControl = firstDescendant(in: hostingView) else {
            return XCTFail("找不到三段式 tab 控件")
        }
        XCTAssertEqual(tabControl.segmentCount, 3)

        viewModel.start()
        let runningHostingView = NSHostingView(rootView: TimerMenuView(viewModel: viewModel))
        runningHostingView.appearance = NSAppearance(named: .aqua)
        runningHostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 500)
        refresh(runningHostingView)
        try writeSnapshot(of: runningHostingView, named: "focus-running")

        guard let runningTabControl: NSSegmentedControl = firstDescendant(in: runningHostingView) else {
            return XCTFail("找不到运行态三段式 tab 控件")
        }
        runningTabControl.selectedSegment = 2
        runningTabControl.sendAction(runningTabControl.action, to: runningTabControl.target)
        refresh(runningHostingView)
        try writeSnapshot(of: runningHostingView, named: "settings-running")

        viewModel.reset()

        for (index, name) in [(1, "stats"), (2, "settings")] {
            tabControl.selectedSegment = index
            tabControl.sendAction(tabControl.action, to: tabControl.target)
            refresh(hostingView)
            try writeSnapshot(of: hostingView, named: name)
        }

        let darkHostingView = NSHostingView(rootView: TimerMenuView(viewModel: viewModel))
        darkHostingView.appearance = NSAppearance(named: .darkAqua)
        darkHostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 500)
        refresh(darkHostingView)
        try writeSnapshot(of: darkHostingView, named: "focus-dark")
    }

    private func completeCurrentMinute() {
        for _ in 0..<60 {
            viewModel.tick()
        }
    }

    private func waitForAsyncWork() async {
        for _ in 0..<5 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func writeSnapshot(of view: NSView, named name: String) throws {
        view.needsDisplay = true
        view.displayIfNeeded()

        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return XCTFail("无法创建 \(name) 快照")
        }

        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return XCTFail("无法创建 \(name) 绘制上下文")
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            view.displayIgnoringOpacity(view.bounds, in: context)
            context.compositingOperation = .destinationOver
            NSColor(calibratedWhite: isDark ? 0.11 : 0.97, alpha: 1).setFill()
            NSBezierPath(rect: view.bounds).fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return XCTFail("无法编码 \(name) 快照")
        }

        try pngData.write(to: URL(fileURLWithPath: "/private/tmp/tomato-timer-v2-\(name).png"))
        XCTAssertGreaterThan(pngData.count, 10_000)
    }

    private func refresh(_ view: NSView) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        view.needsDisplay = true
        view.displayIfNeeded()
    }

    private func firstDescendant<ViewType: NSView>(in view: NSView) -> ViewType? {
        if let match = view as? ViewType {
            return match
        }

        for subview in view.subviews {
            if let match: ViewType = firstDescendant(in: subview) {
                return match
            }
        }

        return nil
    }

    private static func makeDate(year: Int, month: Int, day: Int) -> Date {
        DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: year,
            month: month,
            day: day,
            hour: 12
        ).date!
    }

}

private final class MockNotificationService: NotificationService {
    var authorizationRequestCount = 0
    var nextPhases: [TimerPhase] = []

    func requestAuthorizationIfNeeded() {
        authorizationRequestCount += 1
    }

    func sendPhaseFinishedNotification(nextPhase: TimerPhase) {
        nextPhases.append(nextPhase)
    }
}

private final class MockScreenRecordingService: ScreenRecordingService, @unchecked Sendable {
    var authorizationRequestCount = 0
    var authorizationResult = true
    var startCount = 0
    var pauseCount = 0
    var resumeCount = 0
    var finishCount = 0
    var discardCount = 0
    var startedSpeeds: [ScreenRecordingSpeed] = []
    var startError: Error?
    var resumeError: Error?
    var finishError: Error?

    func requestAuthorizationIfNeeded() -> Bool {
        authorizationRequestCount += 1
        return authorizationResult
    }

    func startRecordingFocusSession(speed: ScreenRecordingSpeed) async throws {
        startCount += 1
        startedSpeeds.append(speed)
        if let startError {
            throw startError
        }
    }

    func pauseRecording() {
        pauseCount += 1
    }

    func resumeRecording() async throws {
        resumeCount += 1
        if let resumeError {
            throw resumeError
        }
    }

    func finishAndSaveRecording() async throws -> URL? {
        finishCount += 1
        if let finishError {
            throw finishError
        }
        return URL(fileURLWithPath: "/tmp/TomatoTimer-test.mov")
    }

    func discardRecording() {
        discardCount += 1
    }
}
