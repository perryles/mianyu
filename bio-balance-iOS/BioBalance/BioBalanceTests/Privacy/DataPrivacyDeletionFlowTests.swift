import Foundation
import XCTest
@testable import BioBalance

/// 「删除我的数据」二次确认状态机测试。
///
/// 验证破坏性操作红线（硬约束：删除必须二次确认）：
/// - 只有「第一次确认（范围说明）→ 最后确认（彻底删除）」两步都完成才执行删除；
/// - 任一步取消都不执行删除，且回到初始状态；
/// - 未经过两步确认直接触发删除被忽略（fail-closed）；
/// - 删除执行中忽略一切重复请求（防重复触发）。
nonisolated final class DataPrivacyDeletionFlowTests: XCTestCase {

    private final class DeletionCounter {
        var count = 0
        var reports: [UserDataDeletionReport] = []
    }

    @MainActor private func makeFlow(counter: DeletionCounter) -> DataPrivacyDeletionFlow {
        let report = UserDataDeletionReport(
            localSwiftDataCleared: true,
            localRecordCount: 1,
            cloudResults: []
        )
        return DataPrivacyDeletionFlow(deletion: {
            counter.count += 1
            counter.reports.append(report)
            return report
        })
    }

    @MainActor func testDeletionRequiresBothConfirmationSteps() async {
        let counter = DeletionCounter()
        let flow = makeFlow(counter: counter)

        flow.requestDeletion()
        XCTAssertEqual(flow.phase, .awaitingFirstConfirmation)
        XCTAssertEqual(counter.count, 0, "第一次确认后绝不能执行删除")

        flow.proceedToFinalConfirmation()
        XCTAssertEqual(flow.phase, .awaitingFinalConfirmation)
        XCTAssertEqual(counter.count, 0, "最后确认弹窗展示后仍未执行删除")

        await flow.confirmFinalDeletion()
        XCTAssertEqual(counter.count, 1, "只有明确点击「彻底删除」才执行一次删除")
        XCTAssertEqual(flow.phase, .finished)
        XCTAssertEqual(flow.lastReport?.localRecordCount, 1)
    }

    @MainActor func testFirstConfirmationAloneNeverDeletes() {
        let counter = DeletionCounter()
        let flow = makeFlow(counter: counter)

        flow.requestDeletion()
        flow.proceedToFinalConfirmation()

        // 只完成两次确认中的前一步，流程停在最后确认，不执行删除
        XCTAssertEqual(flow.phase, .awaitingFinalConfirmation)
        XCTAssertEqual(counter.count, 0)
    }

    @MainActor func testCancelAtAnyStepReturnsToIdleWithoutDeleting() async {
        let counter = DeletionCounter()
        let flow = makeFlow(counter: counter)

        // 第一次确认弹窗中取消
        flow.requestDeletion()
        flow.cancelDeletion()
        XCTAssertEqual(flow.phase, .idle)
        XCTAssertEqual(counter.count, 0)

        // 最后确认弹窗中取消
        flow.requestDeletion()
        flow.proceedToFinalConfirmation()
        flow.cancelDeletion()
        XCTAssertEqual(flow.phase, .idle)
        XCTAssertEqual(counter.count, 0)

        // 取消后再次发起，仍需完整走两步确认
        flow.requestDeletion()
        flow.proceedToFinalConfirmation()
        await flow.confirmFinalDeletion()
        XCTAssertEqual(counter.count, 1)
    }

    @MainActor func testConfirmFinalDeletionWithoutFullFlowIsIgnored() async {
        let counter = DeletionCounter()
        let flow = makeFlow(counter: counter)

        // 从未发起删除就直接确认 → 被忽略（fail-closed）
        await flow.confirmFinalDeletion()
        XCTAssertEqual(counter.count, 0)
        XCTAssertEqual(flow.phase, .idle)

        // 只完成第一次确认（未到最后确认）就确认 → 同样被忽略
        flow.requestDeletion()
        await flow.confirmFinalDeletion()
        XCTAssertEqual(counter.count, 0)
        XCTAssertEqual(flow.phase, .awaitingFirstConfirmation)
    }

    @MainActor func testReentrantRequestsDuringDeletionAreIgnored() async throws {
        let counter = DeletionCounter()
        var resumeDeletion: (() -> Void)?
        let flow = DataPrivacyDeletionFlow(deletion: {
            counter.count += 1
            await withCheckedContinuation { continuation in
                resumeDeletion = { continuation.resume() }
            }
            return UserDataDeletionReport(
                localSwiftDataCleared: true,
                localRecordCount: 1,
                cloudResults: []
            )
        })

        flow.requestDeletion()
        flow.proceedToFinalConfirmation()

        let first = Task { await flow.confirmFinalDeletion() }
        // 等待删除真正开始（phase == .deleting，deletion 闭包挂起）
        while resumeDeletion == nil {
            await Task.yield()
        }
        XCTAssertEqual(flow.phase, .deleting)

        // 删除执行中：新的请求/确认一律忽略
        flow.requestDeletion()
        flow.proceedToFinalConfirmation()
        await flow.confirmFinalDeletion()

        resumeDeletion?()
        await first.value

        XCTAssertEqual(counter.count, 1, "删除执行中重复触发必须被忽略")
        XCTAssertEqual(flow.phase, .finished)
    }
}
