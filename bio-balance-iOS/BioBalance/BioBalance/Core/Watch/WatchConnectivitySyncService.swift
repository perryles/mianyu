import Foundation
import WatchConnectivity
import OSLog

// WCSession 的 Objective-C reply block 未标注 Sendable，但允许在任意队列回复。
// 此桥接只持有不可变的系统回调；可变的一次性状态由锁保护，执行时不持锁。
nonisolated private final class WatchReplyOnce: @unchecked Sendable {
    private let handler: ([String: Any]) -> Void
    private let lock = NSLock()
    private var didReply = false

    init(replyHandler: @escaping ([String: Any]) -> Void) {
        handler = replyHandler
    }

    func send(_ payload: [String: Any]) {
        let shouldReply = lock.withLock {
            guard !didReply else { return false }
            didReply = true
            return true
        }
        if shouldReply { handler(payload) }
    }
}

enum WatchSessionState: Equatable {
    case notSupported
    case notActivated
    case inactive
    case activated

    init(_ activationState: WCSessionActivationState) {
        switch activationState {
        case .notActivated:
            self = .notActivated
        case .inactive:
            self = .inactive
        case .activated:
            self = .activated
        @unknown default:
            self = .notActivated
        }
    }
}

@MainActor
@Observable
final class WatchConnectivitySyncService: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivitySyncService()
    nonisolated private static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "WatchSync")

    private(set) var isWatchReachable = false
    private(set) var watchActivationState: WatchSessionState = .notActivated
    private(set) var lastWatchSyncDate: Date?

    nonisolated static let cachedPayloadKey = "watch.sync.cachedPayload.v1"
    private let watchCachedPayloadKey = cachedPayloadKey

    private static let payloadProcessingQueue = DispatchQueue(
        label: "com.boundesu.BioBalance.WatchSyncPayload",
        qos: .utility
    )
    private static let minimumComplicationTransferInterval: TimeInterval = 300
    private static let minimumRealtimeMessageInterval: TimeInterval = 2
    private static let duplicateFlushRetention: TimeInterval = 60

    private var lastWatchFlushAt: Date?
    private var lastPreferredPayload: [String: Any]?
    private var lastFlushedPayloadSignature: String?
    private var lastComplicationSignature: String?
    private var lastComplicationTransferAt: Date?
    private var lastRealtimeMessageAt: Date?
    private var lastRealtimeSignature: String?
    private var lastComplicationTemplate: String?
    private var notificationTask: Task<Void, Never>?
    private var actionStateNotificationTask: Task<Void, Never>?

    var onRequestSnapshot: ((String?) -> [String: Any])?
    var onRecordHabit: ((String, Int, (@escaping ([String: Any]?) -> Void)) -> Void)?
    var onComplicationTemplate: ((String) -> Void)?
    var onAIQuestion: ((String, (@escaping ([String: Any]?) -> Void)) -> Void)?
    var onSnapshotReceived: ((WatchSyncSnapshot) -> Void)?
    var onRealtimeVitalsReceived: ((WatchRealtimeVitals) -> Void)?

    var isWatchPaired: Bool {
        guard WCSession.isSupported() else { return false }
        return WCSession.default.isPaired
    }

    var isWatchAppInstalled: Bool {
        guard WCSession.isSupported() else { return false }
        return WCSession.default.isWatchAppInstalled
    }

    override init() {
        super.init()
        let planDidChange = Notification.Name.dailyRecoveryPlanDidChange
        let actionStateDidChange = Notification.Name.dailyRecoveryActionStateDidChange
        notificationTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: planDidChange) {
                guard !Task.isCancelled else { return }
                RecoveryPlanWidgetSyncCoordinator.synchronize()
                self?.refreshLatestSnapshot()
            }
        }
        actionStateNotificationTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: actionStateDidChange) {
                guard !Task.isCancelled else { return }
                RecoveryPlanWidgetSyncCoordinator.synchronize()
                self?.refreshLatestSnapshot()
            }
        }
    }

    isolated deinit {
        notificationTask?.cancel()
        actionStateNotificationTask?.cancel()
    }

    func activateIfNeeded() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        refreshSessionState()
    }

    func refreshSessionState(_ session: WCSession = .default) {
        guard WCSession.isSupported() else { return }
        isWatchReachable = session.isReachable
        watchActivationState = WatchSessionState(session.activationState)
    }

    func refreshSessionState() {
        guard WCSession.isSupported() else {
            watchActivationState = .notSupported
            isWatchReachable = false
            return
        }
        refreshSessionState(WCSession.default)
    }

    func clearCachedState() {
        let key = watchCachedPayloadKey
        UserDefaults.standard.removeObject(forKey: key)
        lastWatchSyncDate = nil
        lastWatchFlushAt = nil
        lastPreferredPayload = nil
        lastFlushedPayloadSignature = nil
        lastComplicationSignature = nil
        lastComplicationTransferAt = nil
        lastRealtimeMessageAt = nil
        lastRealtimeSignature = nil
        lastComplicationTemplate = nil
    }

    func syncSnapshot(_ payload: [String: Any], preferred: Bool = true) {
        syncSnapshot(payload, preferred: preferred, force: false)
    }

    func refreshLatestSnapshot() {
        let payload: [String: Any]
        if let latest = onRequestSnapshot?(nil), !latest.isEmpty {
            payload = latest
        } else if let cached = lastPreferredPayload ?? loadCachedWatchPayload(), !cached.isEmpty {
            payload = cached
        } else {
            return
        }
        syncSnapshot(payload, preferred: true, force: true)
    }

    private func syncSnapshot(_ payload: [String: Any], preferred: Bool, force: Bool) {
        guard WCSession.isSupported() else { return }
        let sanitized = WatchSnapshotArbitration.sanitizedSnapshotPayload(payload) ?? payload
        guard !sanitized.isEmpty else { return }
        if preferred {
            lastPreferredPayload = sanitized
            persistCachedPayload(sanitized)
        }
        flushLatestToWatch(preferredPayload: sanitized, force: force)
        transferComplicationIfNeeded(sanitized)
    }

    func syncComplicationTemplate(_ template: String) {
        guard WCSession.isSupported(),
              !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let payload = WatchSyncEnvelope
            .complicationTemplate(template: template, requestId: UUID().uuidString)
            .toDictionary()
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let now = Date()
        if let lastComplicationTransferAt,
           lastComplicationTemplate == template,
           now.timeIntervalSince(lastComplicationTransferAt) < Self.duplicateFlushRetention {
            return
        }
        lastComplicationTemplate = template
        lastComplicationTransferAt = now

        session.transferUserInfo(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    /// 把自定义主题的全部素材文件排队传输到手表；返回是否成功入队。
    @discardableResult
    func transferThemeFiles(theme: CustomWatchTheme) -> Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        guard session.activationState == .activated else { return false }

        var queuedCount = 0
        for (slot, media) in theme.slots {
            let url = WatchCustomThemeFileStore.slotFileURL(
                themeId: theme.id,
                slot: slot,
                fileExtension: media.fileExtension
            )
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let metadata: [String: Any] = [
                WatchCustomThemeFileStore.MetaKey.themeId: theme.id,
                WatchCustomThemeFileStore.MetaKey.themeName: theme.name,
                WatchCustomThemeFileStore.MetaKey.slot: slot.rawValue,
                WatchCustomThemeFileStore.MetaKey.fileExtension: media.fileExtension,
                WatchCustomThemeFileStore.MetaKey.isAnimated: media.isAnimated,
                WatchCustomThemeFileStore.MetaKey.fileSize: media.fileSize,
                WatchCustomThemeFileStore.MetaKey.version: WatchCustomThemeFileStore.metaVersion
            ]
            session.transferFile(url, metadata: metadata)
            queuedCount += 1
        }
        Self.logger.info("[WatchSync][iPhone] theme file transfer queued theme=\(theme.id, privacy: .public) files=\(queuedCount)")
        return queuedCount > 0
    }

    /// 主题被删除时通知手表清理本地素材。
    func removeWatchThemeFiles(themeId: String) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let payload: [String: Any] = [
            "schemaVersion": WatchSyncEnvelope.schemaVersion,
            "type": "watch_theme_removed",
            WatchCustomThemeFileStore.MetaKey.themeId: themeId
        ]
        session.transferUserInfo(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    private func cacheWatchPayload(_ payload: [String: Any]) {
        persistCachedPayload(payload)
    }

    private func persistCachedPayload(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let key = watchCachedPayloadKey
        Self.payloadProcessingQueue.async {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadCachedWatchPayload() -> [String: Any]? {
        guard let data = UserDefaults.standard.data(forKey: watchCachedPayloadKey) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              !object.isEmpty else {
            UserDefaults.standard.removeObject(forKey: watchCachedPayloadKey)
            return nil
        }
        return WatchSnapshotArbitration.sanitizedSnapshotPayload(object) ?? object
    }

    private func flushLatestToWatch(preferredPayload: [String: Any]? = nil, force: Bool = false) {
        guard WCSession.isSupported() else { return }
        let now = Date()
        let payload = preferredPayload ?? lastPreferredPayload ?? loadCachedWatchPayload() ?? onRequestSnapshot?(nil) ?? [:]
        guard payload.isEmpty == false else { return }

        let signature = WatchSnapshotArbitration.payloadSignature(payload)
        if !force,
           let lastWatchFlushAt,
           let lastFlushedPayloadSignature,
           lastFlushedPayloadSignature == signature,
           now.timeIntervalSince(lastWatchFlushAt) < Self.duplicateFlushRetention {
            return
        }
        if !force, let lastWatchFlushAt, now.timeIntervalSince(lastWatchFlushAt) < 1.0 {
            return
        }

        cacheWatchPayload(payload)

        let session = WCSession.default
        guard session.activationState == .activated else { return }
        // 只对成功发送进行节流；激活可能晚于之前的调用完成，因此该回调必须能立即发送。
        lastWatchFlushAt = now

        do {
            try session.updateApplicationContext(payload)
            lastFlushedPayloadSignature = signature
            Self.logger.info("[WatchSync][iPhone] updateApplicationContext succeeded reachable=\(session.isReachable, privacy: .public)")
        } catch let error as WCError where error.code == .payloadTooLarge {
            Self.logger.warning("[WatchSync][iPhone] applicationContext too large fallback transferUserInfo size=\(WatchSnapshotArbitration.payloadByteCount(payload), privacy: .public)")
            session.transferUserInfo(payload)
            lastFlushedPayloadSignature = signature
            persistCachedPayload(payload)
        } catch {
            Self.logger.error("[WatchSync][iPhone] updateApplicationContext failed error=\(error.localizedDescription, privacy: .public)")
            persistCachedPayload(payload)
        }

        lastWatchSyncDate = Date()

        guard session.isReachable else { return }
        Self.logger.info("[WatchSync][iPhone] sendMessage realtime attempt")
        sendRealtimeMessage(payload, signature: signature, force: force)
    }

    private func sendRealtimeMessage(_ payload: [String: Any], signature: String, force: Bool) {
        let session = WCSession.default
        guard session.isReachable else { return }

        let now = Date()
        if !force,
           let lastRealtimeMessageAt,
           let lastRealtimeSignature,
           lastRealtimeSignature == signature,
           now.timeIntervalSince(lastRealtimeMessageAt) < Self.duplicateFlushRetention {
            return
        }
        if !force,
           let lastRealtimeMessageAt,
           now.timeIntervalSince(lastRealtimeMessageAt) < Self.minimumRealtimeMessageInterval {
            return
        }

        lastRealtimeMessageAt = now
        lastRealtimeSignature = signature
        sendMessageWithRetry(payload, remainingAttempts: 2)
    }

    private func transferComplicationIfNeeded(_ payload: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isComplicationEnabled else { return }

        guard session.remainingComplicationUserInfoTransfers > 0 else {
            Self.logger.info("[WatchSync][iPhone] complication transfer budget exhausted remaining=0")
            return
        }

        let now = Date()
        let signature = WatchSnapshotArbitration.payloadSignature(payload)
        if let lastComplicationSignature,
           lastComplicationSignature == signature,
           let lastComplicationTransferAt,
           now.timeIntervalSince(lastComplicationTransferAt) < Self.duplicateFlushRetention {
            return
        }
        if let lastComplicationTransferAt,
           now.timeIntervalSince(lastComplicationTransferAt) < Self.minimumComplicationTransferInterval {
            return
        }

        lastComplicationSignature = signature
        lastComplicationTransferAt = now
        session.transferCurrentComplicationUserInfo(payload)
    }

    private func sendMessageWithRetry(_ payload: [String: Any], remainingAttempts: Int) {
        let session = WCSession.default
        guard session.isReachable else { return }
        let retryData = try? PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
        session.sendMessage(payload, replyHandler: nil) { @Sendable error in
            if let wcError = error as? WCError, wcError.code == .notReachable {
                Self.logger.error("[WatchSync][iPhone] sendMessage failed notReachable")
                return
            }
            Self.logger.error("[WatchSync][iPhone] sendMessage failed error=\(error.localizedDescription, privacy: .public) retriesLeft=\(remainingAttempts, privacy: .public)")
            guard remainingAttempts > 0, let retryData else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                guard let retryPayload = try? PropertyListSerialization.propertyList(from: retryData, format: nil) as? [String: Any] else { return }
                self.sendMessageWithRetry(retryPayload, remainingAttempts: remainingAttempts - 1)
            }
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let isReachable = session.isReachable
        Task { @MainActor in
            if let error {
                Self.logger.error("[WatchSync][iPhone] activation failed error=\(error.localizedDescription, privacy: .public)")
            }
            Self.logger.info("[WatchSync][iPhone] activation state=\(String(describing: activationState.rawValue), privacy: .public) reachable=\(isReachable, privacy: .public)")
            refreshSessionState()
            flushLatestToWatch()
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            WCSession.default.activate()
            refreshSessionState(WCSession.default)
        }
    }
    #endif

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        Task { @MainActor in
            Self.logger.info("[WatchSync][iPhone] reachability changed reachable=\(isReachable, privacy: .public)")
            refreshSessionState()
            flushLatestToWatch()
        }
    }

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        if let error {
            Self.logger.warning("[WatchSync][iPhone] userInfo transfer failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        let envelope = WatchSyncEnvelope.fromDictionary(message)
        Task { @MainActor in
            handleIncomingWatchEnvelope(envelope)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        let envelope = WatchSyncEnvelope.fromDictionary(applicationContext)
        Task { @MainActor in
            handleIncomingWatchEnvelope(envelope)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        let envelope = WatchSyncEnvelope.fromDictionary(userInfo)
        Task { @MainActor in
            handleIncomingWatchEnvelope(envelope)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        let envelope = WatchSyncEnvelope.fromDictionary(message)
        let reply = WatchReplyOnce(replyHandler: replyHandler)
        Task { @MainActor in
            handleMessage(envelope, reply: reply)
        }
    }

    private func handleMessage(_ envelope: WatchSyncEnvelope, reply: WatchReplyOnce) {
        switch envelope {
        case .requestSnapshot(let requestId):
            reply.send(onRequestSnapshot?(requestId) ?? [:])
        case .recordHabit(let type, let amount, _):
            guard !type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, amount >= 0 else {
                reply.send([:])
                return
            }
            guard let onRecordHabit else {
                reply.send([:])
                return
            }
            onRecordHabit(type, amount) { payload in
                reply.send(payload ?? [:])
            }
        case .aiQuestion(let question, _):
            guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                reply.send([:])
                return
            }
            guard let onAIQuestion else {
                reply.send([:])
                return
            }
            onAIQuestion(question) { payload in
                reply.send(payload ?? [:])
            }
        default:
            reply.send([:])
        }
    }

    private func handleIncomingWatchEnvelope(_ envelope: WatchSyncEnvelope) {
        switch envelope {
        case .requestSnapshot:
            flushLatestToWatch()
        case .recordHabit(let type, let amount, _):
            guard !type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, amount >= 0 else { break }
            onRecordHabit?(type, amount) { _ in }
        case .complicationTemplate(let template, _):
            guard !template.isEmpty else { break }
            onComplicationTemplate?(template)
        case .snapshot(let snapshot, _):
            onSnapshotReceived?(snapshot)
        case .realtimeVitals(let vitals, _):
            onRealtimeVitalsReceived?(vitals)
        case .aiQuestion(let question, _):
            guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { break }
            onAIQuestion?(question) { _ in }
        default:
            break
        }
    }
}
