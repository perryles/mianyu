import AppIntentsTesting
import XCTest

nonisolated final class AppIntentsTestingFrameworkTests: XCTestCase {
    @MainActor func testWidgetIntentDefinitionCanBeCreatedWithoutLinkingWidgetTypes() throws {
        guard #available(iOS 27.0, *) else {
            throw XCTSkip("App Intents Testing requires iOS 27 or later.")
        }

        let widgetBundleIdentifier = "com.boundesu.BioBalance.BioBalanceWidget"
        let definitions = IntentDefinitions(bundleIdentifier: widgetBundleIdentifier)
        let intent = definitions.intents["QuickHydrationIntent"]

        XCTAssertEqual(intent.bundleIdentifier, widgetBundleIdentifier)
        XCTAssertEqual(intent.identifier, "QuickHydrationIntent")
    }
}
