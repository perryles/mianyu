import Foundation

/// Serializes success and expiration on MainActor. Cancellation is cooperative:
/// an operation that finishes after expiration must not publish or finish again.
@MainActor
final class WidgetBackgroundRefreshExecution {
    private var work: Task<Void, Never>?
    private var completion: ((Bool) -> Void)?
    private(set) var isFinished = false

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    @discardableResult
    func start(
        operation: @escaping @MainActor () async -> Void,
        publish: @escaping @MainActor () -> Void
    ) -> Task<Void, Never>? {
        guard !isFinished, work == nil else { return nil }
        let task = Task { @MainActor in
            guard !Task.isCancelled, !self.isFinished else {
                self.finish(success: false)
                return
            }
            await operation()
            guard !Task.isCancelled, !self.isFinished else {
                self.finish(success: false)
                return
            }
            publish()
            self.finish(success: true)
        }
        work = task
        return task
    }

    func expire() {
        guard !isFinished else { return }
        work?.cancel()
        finish(success: false)
    }

    private func finish(success: Bool) {
        guard !isFinished else { return }
        isFinished = true
        work = nil
        let callback = completion
        completion = nil
        callback?(success)
    }
}
