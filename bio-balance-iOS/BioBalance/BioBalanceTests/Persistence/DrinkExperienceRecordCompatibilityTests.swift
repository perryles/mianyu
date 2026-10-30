import Foundation
import XCTest
@testable import BioBalance

nonisolated final class DrinkExperienceRecordCompatibilityTests: XCTestCase {
    @MainActor func testLegacyDrinkRecordWithoutAISourceStillDecodes() throws {
        let data = Data(
            #"{"id":"drink-1","storeName":"咖啡店","drinkName":"冰美式","capturedAt":0,"status":"confirmed","isGeneratedFromRecognition":true}"#.utf8
        )

        let record = try JSONDecoder().decode(DrinkStampRecord.self, from: data)

        XCTAssertEqual(record.id, "drink-1")
        XCTAssertNil(record.aiProviderID)
        XCTAssertNil(record.aiModel)
        XCTAssertNil(record.aiConfidence)
        XCTAssertNil(record.aiSourceLabel)
    }

    @MainActor func testLegacyMealRecordWithoutAISourceStillDecodes() throws {
        let data = Data(
            #"{"id":"meal-1","mealSlot":"lunch","recognizedFoods":[{"id":"food-1","name":"沙拉","calories":180}],"estimatedCalories":180,"capturedAt":0}"#.utf8
        )

        let record = try JSONDecoder().decode(MealRecognitionRecord.self, from: data)

        XCTAssertEqual(record.id, "meal-1")
        XCTAssertNil(record.aiProviderID)
        XCTAssertNil(record.aiModel)
        XCTAssertNil(record.aiConfidence)
        XCTAssertNil(record.aiSourceLabel)
    }
}
