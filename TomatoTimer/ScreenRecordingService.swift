import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import os
import ScreenCaptureKit

enum ScreenRecordingSpeed: Int, CaseIterable, Identifiable, Sendable {
    case five = 5
    case ten = 10
    case twenty = 20

    var id: Int { rawValue }

    var shortTitle: String {
        "\(rawValue)x"
    }

    var storageEstimateTitle: String {
        switch self {
        case .five:
            return "约 120M/30分钟"
        case .ten:
            return "约60M/30分钟"
        case .twenty:
            return "约30M/30分钟"
        }
    }
}

protocol ScreenRecordingService: AnyObject, Sendable {
    func requestAuthorizationIfNeeded() -> Bool
    func startRecordingFocusSession(speed: ScreenRecordingSpeed) async throws
    func pauseRecording()
    func resumeRecording() async throws
    func finishAndSaveRecording() async throws -> URL?
    func discardRecording()
}

enum ScreenRecordingError: LocalizedError {
    case mainDisplayUnavailable
    case screenCapturePermissionDenied
    case recordingUnavailable
    case noFramesCaptured
    case writingFailed(String)

    var errorDescription: String? {
        switch self {
        case .mainDisplayUnavailable:
            return "找不到主屏幕"
        case .screenCapturePermissionDenied:
            return "请在系统设置中允许屏幕录制后重启应用"
        case .recordingUnavailable:
            return "需要授权屏幕录制"
        case .noFramesCaptured:
            return "录屏失败：没有捕获到完整画面"
        case .writingFailed(let message):
            return "录屏失败：\(message)"
        }
    }
}

final class SystemScreenRecordingService: NSObject, ScreenRecordingService, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private static let recordingDirectoryPathKey = "speedRecordingDirectoryPath"

    private let captureQueue = DispatchQueue(label: "com.local.TomatoTimer.screenRecording")
    private static let captureQueueKey = DispatchSpecificKey<Void>()
    private let logger = Logger(subsystem: "com.local.TomatoTimer", category: "SpeedRecording")
    private let fileManager: FileManager
    private let maxOutputLongEdge = 1_920
    private let averageVideoBitRate = 2_700_000

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var latestSampleBuffer: CMSampleBuffer?
    private var frameAppendTimer: DispatchSourceTimer?
    private var isPaused = false
    private var isRecording = false
    private var frameIndex: Int64 = 0
    private var hasLoggedFirstCompleteFrame = false
    private var appendFailureMessage: String?
    private var wasStoppedBySystem = false
    private var outputSize: CaptureOutputSize?
    private var speedMultiplier: Int32 = Int32(ScreenRecordingSpeed.ten.rawValue)

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        super.init()
        captureQueue.setSpecific(key: Self.captureQueueKey, value: ())
    }

    func requestAuthorizationIfNeeded() -> Bool {
        logCurrentAppIdentity()
        return requestScreenCaptureAccessIfNeeded()
    }

    func startRecordingFocusSession(speed: ScreenRecordingSpeed) async throws {
        guard !captureQueueSync({ isRecording }) else {
            try await resumeRecording()
            return
        }

        logger.info("Speed recording start requested")
        logCurrentAppIdentity()
        guard requestScreenCaptureAccessIfNeeded() else {
            throw ScreenRecordingError.screenCapturePermissionDenied
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
            logger.error("No display available for speed recording")
            throw ScreenRecordingError.mainDisplayUnavailable
        }

        let outputSize = CaptureOutputSize(
            Self.scaledSize(width: display.width, height: display.height, maxLongEdge: maxOutputLongEdge)
        )
        let url = try Self.makeTemporaryOutputURL(fileManager: fileManager)
        logger.info(
            "Selected display id=\(display.displayID, privacy: .public), input=\(display.width, privacy: .public)x\(display.height, privacy: .public), output=\(outputSize.width, privacy: .public)x\(outputSize.height, privacy: .public), temp=\(url.path, privacy: .public)"
        )

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: outputSize.width,
                AVVideoHeightKey: outputSize.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: averageVideoBitRate
                ]
            ]
        )
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            logger.error("AVAssetWriter cannot add video input")
            throw ScreenRecordingError.recordingUnavailable
        }

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let stream = try makeStream(display: display, outputSize: outputSize)

        captureQueueSync {
            self.stream = stream
            self.assetWriter = writer
            self.writerInput = input
            self.outputURL = url
            self.latestSampleBuffer = nil
            self.frameAppendTimer = nil
            self.isPaused = false
            self.isRecording = true
            self.frameIndex = 0
            self.hasLoggedFirstCompleteFrame = false
            self.appendFailureMessage = nil
            self.wasStoppedBySystem = false
            self.outputSize = outputSize
            self.speedMultiplier = Int32(speed.rawValue)
        }

        do {
            try await stream.startCapture()
            logger.info("SCStream startCapture succeeded")
            captureQueueAsync {
                self.startFrameAppendTimer()
            }
        } catch {
            logger.error("SCStream startCapture failed: \(error.localizedDescription, privacy: .public)")
            discardRecording()
            throw ScreenRecordingError.recordingUnavailable
        }
    }

    func pauseRecording() {
        captureQueueAsync {
            guard self.isRecording else { return }
            self.isPaused = true
            self.logger.info("Speed recording paused")
        }
    }

    func resumeRecording() async throws {
        enum ResumeMode {
            case inactive
            case normal
            case rebuild(CaptureOutputSize)
        }

        let resumeMode = try captureQueueSync { () throws -> ResumeMode in
            guard self.isRecording else { return .inactive }
            guard let outputSize else {
                throw ScreenRecordingError.recordingUnavailable
            }

            if self.wasStoppedBySystem || self.stream == nil {
                self.isPaused = true
                self.latestSampleBuffer = nil
                self.stopFrameAppendTimer()
                self.logger.info("Speed recording resume requires SCStream rebuild")
                return .rebuild(outputSize)
            }

            self.isPaused = false
            if self.frameAppendTimer == nil {
                self.startFrameAppendTimer()
            }
            self.logger.info("Speed recording resumed")
            return .normal
        }

        guard case .rebuild(let outputSize) = resumeMode else {
            return
        }

        try await rebuildStreamForResume(outputSize: outputSize)
    }

    func finishAndSaveRecording() async throws -> URL? {
        let state = captureQueueSync { () -> RecordingFinishState? in
            guard isRecording else { return nil }

            stopFrameAppendTimer()
            let state = RecordingFinishState(
                stream: stream,
                writer: assetWriter,
                input: writerInput,
                temporaryURL: outputURL,
                frameCount: frameIndex,
                appendFailureMessage: appendFailureMessage,
                wasStoppedBySystem: wasStoppedBySystem
            )
            isRecording = false
            isPaused = false
            self.stream = nil
            assetWriter = nil
            writerInput = nil
            outputURL = nil
            latestSampleBuffer = nil
            appendFailureMessage = nil
            wasStoppedBySystem = false
            outputSize = nil
            return state
        }

        guard let state else {
            logger.info("finishAndSaveRecording ignored because recording is not active")
            return nil
        }

        logger.info("Finishing speed recording. frameCount=\(state.frameCount, privacy: .public), temp=\(state.temporaryURL?.path ?? "nil", privacy: .public)")

        if state.wasStoppedBySystem {
            logger.info("Skipping SCStream stopCapture because stream was already stopped by the system")
        } else {
            do {
                try await state.stream?.stopCapture()
            } catch {
                logger.warning("SCStream stopCapture failed while finishing; continuing writer finish: \(error.localizedDescription, privacy: .public)")
            }
        }
        state.input?.markAsFinished()

        if let writer = state.writer {
            await withCheckedContinuation { continuation in
                writer.finishWriting {
                    continuation.resume()
                }
            }
        }

        let fileSize = state.temporaryURL.flatMap { try? fileManager.attributesOfItem(atPath: $0.path)[.size] as? NSNumber }
        logger.info(
            "AVAssetWriter finished. status=\(Self.writerStatusDescription(state.writer?.status), privacy: .public), error=\(state.writer?.error?.localizedDescription ?? "nil", privacy: .public), tempSize=\(fileSize?.int64Value ?? -1, privacy: .public), temp=\(state.temporaryURL?.path ?? "nil", privacy: .public)"
        )

        if let appendFailureMessage = state.appendFailureMessage {
            logger.error("Append failed earlier: \(appendFailureMessage, privacy: .public)")
            throw ScreenRecordingError.writingFailed(appendFailureMessage)
        }

        guard state.frameCount > 0 else {
            logger.error("No frames were appended. Keeping temp file for debugging: \(state.temporaryURL?.path ?? "nil", privacy: .public)")
            throw ScreenRecordingError.noFramesCaptured
        }

        guard let temporaryURL = state.temporaryURL, state.writer?.status == .completed else {
            let writerError = state.writer?.error?.localizedDescription ?? Self.writerStatusDescription(state.writer?.status)
            logger.error("Writer did not complete. Keeping temp file for debugging: \(state.temporaryURL?.path ?? "nil", privacy: .public)")
            throw ScreenRecordingError.writingFailed(writerError)
        }

        let finalURL = try Self.makeFinalOutputURL(fileManager: fileManager)
        try fileManager.createDirectory(
            at: finalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: finalURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: finalURL)
        logger.info("Speed recording moved to final path: \(finalURL.path, privacy: .public)")
        return finalURL
    }

    func discardRecording() {
        let state = captureQueueSync { () -> RecordingFinishState? in
            guard isRecording || stream != nil || outputURL != nil else { return nil }

            stopFrameAppendTimer()
            let state = RecordingFinishState(
                stream: stream,
                writer: assetWriter,
                input: writerInput,
                temporaryURL: outputURL,
                frameCount: frameIndex,
                appendFailureMessage: appendFailureMessage,
                wasStoppedBySystem: wasStoppedBySystem
            )
            isRecording = false
            isPaused = false
            self.stream = nil
            assetWriter = nil
            writerInput = nil
            outputURL = nil
            latestSampleBuffer = nil
            appendFailureMessage = nil
            wasStoppedBySystem = false
            outputSize = nil
            return state
        }

        guard let state else { return }
        logger.info("Discarding speed recording. frameCount=\(state.frameCount, privacy: .public), temp=\(state.temporaryURL?.path ?? "nil", privacy: .public)")

        Task {
            try? await state.stream?.stopCapture()
            state.writer?.cancelWriting()
            try? state.temporaryURL.map { try fileManager.removeItem(at: $0) }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, isRecording, sampleBuffer.isValid else { return }
        guard let frameStatus = Self.frameStatus(from: sampleBuffer) else {
            logger.debug("Received screen sample without frame status")
            return
        }

        logger.debug("Received screen sample. status=\(Self.frameStatusDescription(frameStatus), privacy: .public)")
        guard frameStatus == .complete else { return }

        if !hasLoggedFirstCompleteFrame {
            hasLoggedFirstCompleteFrame = true
            logger.info("Received first complete screen frame")
        }

        latestSampleBuffer = sampleBuffer
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let stoppedStreamID = ObjectIdentifier(stream)
        captureQueueAsync {
            guard self.stream.map(ObjectIdentifier.init) == stoppedStreamID else { return }
            self.logger.error("SCStream stopped by system: \(error.localizedDescription, privacy: .public)")
            self.wasStoppedBySystem = true
            self.isPaused = true
            self.latestSampleBuffer = nil
            self.stopFrameAppendTimer()
        }
    }

    private func startFrameAppendTimer() {
        stopFrameAppendTimer()

        let timer = DispatchSource.makeTimerSource(queue: captureQueue)
        timer.schedule(deadline: .now(), repeating: 1)
        timer.setEventHandler { [weak self] in
            self?.appendLatestFrame()
        }
        frameAppendTimer = timer
        timer.resume()
    }

    private func stopFrameAppendTimer() {
        frameAppendTimer?.cancel()
        frameAppendTimer = nil
    }

    private func appendLatestFrame() {
        guard isRecording, !isPaused else { return }
        guard let writerInput, writerInput.isReadyForMoreMediaData else { return }
        guard let latestSampleBuffer, latestSampleBuffer.isValid else {
            logger.debug("Append skipped because no complete frame is available yet")
            return
        }

        let frameTime = CMTime(value: frameIndex, timescale: speedMultiplier)

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: speedMultiplier),
            presentationTimeStamp: frameTime,
            decodeTimeStamp: .invalid
        )
        var retimedSampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: latestSampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &retimedSampleBuffer
        )

        guard let retimedSampleBuffer else {
            appendFailureMessage = "CMSampleBufferCreateCopyWithNewTiming failed"
            logger.error("Failed to retime sample buffer at frameIndex=\(self.frameIndex, privacy: .public)")
            return
        }

        let didAppend = writerInput.append(retimedSampleBuffer)
        logger.debug("Append frame index=\(self.frameIndex, privacy: .public), time=\(CMTimeGetSeconds(frameTime), privacy: .public), success=\(didAppend, privacy: .public)")

        if didAppend {
            frameIndex += 1
        } else {
            let message = assetWriter?.error?.localizedDescription ?? "AVAssetWriterInput.append returned false"
            appendFailureMessage = message
            logger.error("Append failed at frameIndex=\(self.frameIndex, privacy: .public): \(message, privacy: .public)")
        }
    }

    private func rebuildStreamForResume(outputSize: CaptureOutputSize) async throws {
        logger.info("Rebuilding SCStream for speed recording resume")
        guard requestScreenCaptureAccessIfNeeded() else {
            throw ScreenRecordingError.screenCapturePermissionDenied
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
            logger.error("No display available while rebuilding speed recording stream")
            throw ScreenRecordingError.mainDisplayUnavailable
        }

        let newStream = try makeStream(display: display, outputSize: outputSize)

        do {
            try await newStream.startCapture()
        } catch {
            logger.error("SCStream restart failed while resuming: \(error.localizedDescription, privacy: .public)")
            throw ScreenRecordingError.recordingUnavailable
        }

        let shouldStopNewStream = captureQueueSync { () -> Bool in
            guard self.isRecording else { return true }

            self.stream = newStream
            self.latestSampleBuffer = nil
            self.isPaused = false
            self.wasStoppedBySystem = false
            self.hasLoggedFirstCompleteFrame = false
            self.startFrameAppendTimer()
            self.logger.info("Speed recording stream rebuilt and resumed")
            return false
        }

        if shouldStopNewStream {
            try? await newStream.stopCapture()
        }
    }

    private func makeStream(display: SCDisplay, outputSize: CaptureOutputSize) throws -> SCStream {
        let configuration = SCStreamConfiguration()
        configuration.width = outputSize.width
        configuration.height = outputSize.height
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 3
        configuration.capturesAudio = false

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
        return stream
    }

    private static func scaledSize(width: Int, height: Int, maxLongEdge: Int) -> (width: Int, height: Int) {
        let longEdge = max(width, height)
        guard longEdge > maxLongEdge else {
            return (width, height)
        }

        let scale = Double(maxLongEdge) / Double(longEdge)
        return (
            width: max(1, Int(Double(width) * scale)),
            height: max(1, Int(Double(height) * scale))
        )
    }

    private static func makeTemporaryOutputURL(fileManager: FileManager) throws -> URL {
        let directory = fileManager.temporaryDirectory.appendingPathComponent("Tomato Timer", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
    }

    private static func makeFinalOutputURL(fileManager: FileManager) throws -> URL {
        let directory = try recordingDirectoryURL(fileManager: fileManager)

        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"

        return directory
            .appendingPathComponent("TomatoTimer-\(formatter.string(from: Date()))")
            .appendingPathExtension("mov")
    }

    static func recordingDirectoryURL(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) throws -> URL {
        if let path = defaults.string(forKey: recordingDirectoryPathKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        let moviesDirectory = try fileManager.url(
            for: .moviesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return moviesDirectory.appendingPathComponent("Tomato Timer", isDirectory: true)
    }

    static func setRecordingDirectoryURL(_ url: URL, defaults: UserDefaults = .standard) {
        defaults.set(url.path, forKey: recordingDirectoryPathKey)
    }

    static func resetRecordingDirectoryURL(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: recordingDirectoryPathKey)
    }

    private func logCurrentAppIdentity() {
        logger.info(
            "Running bundle id=\(Bundle.main.bundleIdentifier ?? "unknown", privacy: .public), bundle=\(Bundle.main.bundleURL.path, privacy: .public), executable=\(Bundle.main.executableURL?.path ?? "unknown", privacy: .public)"
        )
    }

    private func requestScreenCaptureAccessIfNeeded() -> Bool {
        let hasScreenCaptureAccess = CGPreflightScreenCaptureAccess()
        logger.info("Screen capture preflight access=\(hasScreenCaptureAccess, privacy: .public)")
        guard !hasScreenCaptureAccess else {
            logger.info("Screen capture permission already granted")
            return true
        }

        logger.info("Requesting screen capture permission")
        let isGranted = CGRequestScreenCaptureAccess()
        logger.info("Screen capture request result=\(isGranted, privacy: .public)")
        if !isGranted {
            logger.error("Screen capture permission denied before SCShareableContent request")
        }
        return isGranted
    }

    private func captureQueueAsync(_ work: @escaping @Sendable () -> Void) {
        captureQueue.async(execute: work)
    }

    private func captureQueueSync<T>(_ work: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: Self.captureQueueKey) != nil {
            return try work()
        }

        return try captureQueue.sync(execute: work)
    }

    private static func frameStatus(from sampleBuffer: CMSampleBuffer) -> SCFrameStatus? {
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let rawStatus = attachments.first?[.status] as? Int
        else {
            return nil
        }

        return SCFrameStatus(rawValue: rawStatus)
    }

    private static func frameStatusDescription(_ status: SCFrameStatus) -> String {
        switch status {
        case .complete:
            return "complete"
        case .idle:
            return "idle"
        case .blank:
            return "blank"
        case .suspended:
            return "suspended"
        case .started:
            return "started"
        case .stopped:
            return "stopped"
        @unknown default:
            return "unknown(\(status.rawValue))"
        }
    }

    private static func writerStatusDescription(_ status: AVAssetWriter.Status?) -> String {
        guard let status else { return "nil" }

        switch status {
        case .unknown:
            return "unknown"
        case .writing:
            return "writing"
        case .completed:
            return "completed"
        case .failed:
            return "failed"
        case .cancelled:
            return "cancelled"
        @unknown default:
            return "unknown(\(status.rawValue))"
        }
    }
}

private struct RecordingFinishState {
    var stream: SCStream?
    var writer: AVAssetWriter?
    var input: AVAssetWriterInput?
    var temporaryURL: URL?
    var frameCount: Int64
    var appendFailureMessage: String?
    var wasStoppedBySystem: Bool
}

private struct CaptureOutputSize {
    var width: Int
    var height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    init(_ size: (width: Int, height: Int)) {
        self.width = size.width
        self.height = size.height
    }
}
