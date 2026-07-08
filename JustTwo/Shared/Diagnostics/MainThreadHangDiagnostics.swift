import Foundation
#if canImport(QuartzCore)
import QuartzCore
#endif
#if canImport(CoreFoundation)
import CoreFoundation
#endif

#if DEBUG
enum MainThreadHangDiagnostics {
    @MainActor
    static func start() {
        MainThreadHangMonitor.shared.start(thresholdMilliseconds: 150)
        FrameJankMonitor.shared.start()
    }

    @MainActor
    static func stop() {
        MainThreadHangMonitor.shared.stop()
        FrameJankMonitor.shared.stop()
    }
}

private final class MainThreadHangMonitor: @unchecked Sendable {
    static let shared = MainThreadHangMonitor()

    private let stateLock = NSLock()
    private let queue = DispatchQueue(label: "pro.sda.justtwo.main-hang-monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var observer: CFRunLoopObserver?
    private var lastPingNanoseconds = DispatchTime.now().uptimeNanoseconds
    private var lastReportedPingNanoseconds: UInt64 = 0
    private var lastActivityRawValue: CFOptionFlags = 0
    private var thresholdNanoseconds: UInt64 = 150_000_000

    private init() {}

    @MainActor
    func start(thresholdMilliseconds: Int) {
        guard timer == nil, observer == nil else { return }

        thresholdNanoseconds = UInt64(max(50, thresholdMilliseconds)) * 1_000_000
        recordPing(activityRawValue: CFRunLoopActivity.entry.rawValue)

        var context = CFRunLoopObserverContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        observer = CFRunLoopObserverCreate(
            kCFAllocatorDefault,
            CFRunLoopActivity.allActivities.rawValue,
            true,
            0,
            { _, activity, info in
                guard let info else { return }
                let monitor = Unmanaged<MainThreadHangMonitor>.fromOpaque(info).takeUnretainedValue()
                monitor.recordPing(activityRawValue: activity.rawValue)
            },
            &context
        )

        if let observer {
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(thresholdMilliseconds), repeating: .milliseconds(75))
        timer.setEventHandler { [weak self] in
            self?.checkForHang()
        }
        self.timer = timer
        timer.resume()

        NetworkDebug.log("MainThreadHangMonitor started thresholdMs=\(thresholdMilliseconds)")
    }

    @MainActor
    func stop() {
        timer?.cancel()
        timer = nil

        if let observer {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
        observer = nil
        NetworkDebug.log("MainThreadHangMonitor stopped")
    }

    private func recordPing(activityRawValue: CFOptionFlags) {
        let now = DispatchTime.now().uptimeNanoseconds
        stateLock.lock()
        lastPingNanoseconds = now
        lastActivityRawValue = activityRawValue
        stateLock.unlock()
    }

    private func checkForHang() {
        let now = DispatchTime.now().uptimeNanoseconds

        stateLock.lock()
        let ping = lastPingNanoseconds
        let lastReported = lastReportedPingNanoseconds
        let activity = lastActivityRawValue
        let threshold = thresholdNanoseconds
        stateLock.unlock()

        guard now > ping, now - ping >= threshold, ping != lastReported else { return }

        stateLock.lock()
        lastReportedPingNanoseconds = ping
        stateLock.unlock()

        let durationMilliseconds = Int((now - ping) / 1_000_000)
        NetworkDebug.log(
            "Main hang suspected durationMs=\(durationMilliseconds) lastRunLoopActivity=\(activity)"
        )
    }
}

@MainActor
private final class FrameJankMonitor: NSObject {
    static let shared = FrameJankMonitor()

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var droppedFrames = 0
    private var totalFrames = 0
    private var lastLogTimestamp: CFTimeInterval = 0

    func start() {
        guard displayLink == nil else { return }
        lastTimestamp = 0
        droppedFrames = 0
        totalFrames = 0
        lastLogTimestamp = CACurrentMediaTime()

        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        NetworkDebug.log("FrameJankMonitor started")
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        NetworkDebug.log("FrameJankMonitor stopped")
    }

    @objc private func tick(_ link: CADisplayLink) {
        totalFrames += 1
        defer { lastTimestamp = link.timestamp }

        guard lastTimestamp > 0 else { return }

        let delta = link.timestamp - lastTimestamp
        let targetFrameDuration = max(1.0 / 120.0, link.targetTimestamp - link.timestamp)
        let missedFrameThreshold = max(0.025, targetFrameDuration * 2.5)
        guard delta >= missedFrameThreshold else { return }

        droppedFrames += max(1, Int((delta / max(targetFrameDuration, 0.001)).rounded()) - 1)

        let now = CACurrentMediaTime()
        guard now - lastLogTimestamp >= 1 else { return }
        lastLogTimestamp = now

        let dropRate = totalFrames > 0 ? Double(droppedFrames) / Double(totalFrames) : 0
        NetworkDebug.log(
            "Frame jank deltaMs=\(Int(delta * 1_000)) droppedFrames=\(droppedFrames) totalFrames=\(totalFrames) dropRate=\(String(format: "%.2f", dropRate))"
        )
    }
}
#endif
