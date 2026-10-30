import XCTest
@testable import BioBalance

nonisolated final class MealRecognitionTests: XCTestCase {
    @MainActor func testNutritionSummaryAggregatesOnlyFoodItems() {
        let foods = [
            MealFoodItem(id: "1", name: "A", calories: 120, proteinGrams: 10, carbohydrateGrams: 15, fatGrams: 2, fiberGrams: 3),
            MealFoodItem(id: "2", name: "B", calories: 80, proteinGrams: 4, carbohydrateGrams: 8, fatGrams: 5, fiberGrams: 1)
        ]
        let result = MealNutritionSummary.calculate(from: foods)
        XCTAssertEqual(result.calories, 200)
        XCTAssertEqual(result.proteinGrams, 14)
        XCTAssertEqual(result.carbohydrateGrams, 23)
        XCTAssertEqual(result.fatGrams, 7)
        XCTAssertEqual(result.fiberGrams, 4)
    }

    @MainActor func testServingChangeScalesEveryNutrientAndMarksUserEdit() {
        let food = MealFoodItem(id: "1", name: "A", calories: 100, proteinGrams: 10, carbohydrateGrams: 20, fatGrams: 5, fiberGrams: 2, servingAmount: 100, servingUnit: "g", nutritionSource: .aiEstimate)
        let result = food.scaled(to: 150)
        XCTAssertEqual(result.calories, 150)
        XCTAssertEqual(result.proteinGrams, 15)
        XCTAssertEqual(result.carbohydrateGrams, 30)
        XCTAssertEqual(result.fatGrams, 7.5)
        XCTAssertEqual(result.fiberGrams, 3)
        XCTAssertTrue(result.wasEditedByUser)
    }

    @MainActor func testStructuredDecoderRejectsNegativeNutrition() {
        let json = Data(#"{"status":"recognized","primaryName":"meal","confidence":0.9,"estimatedCalories":100,"foods":[{"name":"food","calories":100,"confidence":0.9,"proteinGrams":-1}],"warnings":[],"reason":null}"#.utf8)
        XCTAssertThrowsError(try AIMealStructuredResponseDecoder.decode(json, provider: .qwen, model: "test"))
    }

    @MainActor func testStructuredDecoderUsesFoodSumAndPreservesEstimateMetadata() throws {
        let json = Data(#"{"status":"needs_review","primaryName":"meal","confidence":0.7,"estimatedCalories":999,"foods":[{"name":"food","calories":100,"confidence":0.6,"estimatedAmount":120,"unit":"g","proteinGrams":20,"carbohydrateGrams":4,"fatGrams":3,"fiberGrams":2}],"warnings":["estimate"],"reason":null}"#.utf8)
        let result: AIMealAnalysisResult
        do {
            result = try AIMealStructuredResponseDecoder.decode(json, provider: .qwen, model: "test")
        } catch {
            XCTFail("decode threw: \(error)")
            throw error
        }
        XCTAssertEqual(result.estimatedCalories, 100)
        XCTAssertEqual(result.foods.first?.estimatedAmount, 120)
        XCTAssertEqual(result.foods.first?.fiberGrams, 2)
        XCTAssertTrue(result.requiresReview)
    }

    // MARK: - 识别失败分类（MealRecognitionFailure）

    @MainActor func testFailureClassificationMapsOfflineAndTimeoutErrors() {
        let offline = MealRecognitionFailure(error: URLError(.notConnectedToInternet))
        XCTAssertEqual(offline, .networkUnavailable)
        XCTAssertEqual(offline.diagnosticCode, "network_unavailable")

        let timeout = MealRecognitionFailure(error: PhotoRecognitionServiceError.timedOut)
        XCTAssertEqual(timeout, .timeout)

        let cancelled = MealRecognitionFailure(error: URLError(.cancelled))
        XCTAssertEqual(cancelled, .cancelled)
    }

    @MainActor func testFailureClassificationMapsImageErrors() {
        XCTAssertEqual(
            MealRecognitionFailure(error: PhotoRecognitionServiceError.invalidPhotoData),
            .invalidImage
        )
        XCTAssertEqual(
            MealRecognitionFailure(error: PhotoRecognitionServiceError.imageTooLarge),
            .imageTooLarge
        )
    }

    // MARK: - 搜索结果解码与校验（MealFoodSearchService）

    @MainActor func testFoodSearchDecoderKeepsValidItemsAndMarksAIEstimate() throws {
        let json = Data(#"{"items":[{"name":"鸡胸肉","calories":133,"servingAmount":100,"unit":"g","proteinGrams":31,"carbohydrateGrams":0,"fatGrams":3.6,"fiberGrams":0},{"name":"糙米饭","calories":112,"proteinGrams":2.6}]}"#.utf8)
        let items = try MealFoodSearchService.decodeItems(from: json)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?.nutritionSource, .aiEstimate)
        XCTAssertEqual(items.first?.name, "鸡胸肉")
        XCTAssertNil(items.last?.fiberGrams)
    }

    @MainActor func testFoodSearchDecoderRejectsNegativeAndOversizedValues() throws {
        let json = Data(#"{"items":[{"name":"坏数据","calories":-50},{"name":"超大量","calories":99999},{"name":"合法","calories":120}]}"#.utf8)
        let items = try MealFoodSearchService.decodeItems(from: json)
        XCTAssertEqual(items.map(\.name), ["合法"])
    }

    @MainActor func testFoodSearchDecoderThrowsOnMalformedPayload() {
        let json = Data(#"{"unexpected":true}"#.utf8)
        XCTAssertThrowsError(try MealFoodSearchService.decodeItems(from: json))
    }

    // MARK: - 复制餐食（营养字段保真）

    @MainActor func testCopiedMealKeepsNutritionFieldsButGetsNewIdentity() {
        let original = MealRecognitionRecord(
            id: "record-1",
            mealSlot: .lunch,
            recognizedFoods: [
                MealFoodItem(
                    id: "food-1",
                    name: "鸡胸肉",
                    calories: 248,
                    proteinGrams: 46,
                    carbohydrateGrams: 0,
                    fatGrams: 5.4,
                    fiberGrams: 0,
                    servingAmount: 150,
                    servingUnit: "g",
                    confidence: 0.82,
                    nutritionSource: .aiEstimate,
                    wasEditedByUser: true
                )
            ],
            estimatedCalories: 248,
            photoFileID: nil,
            photoURL: nil,
            capturedAt: Date(timeIntervalSince1970: 1_000),
            locationSummary: nil,
            aiProviderID: "qwen",
            aiModel: "qwen-vl-max",
            aiConfidence: 0.82,
            wasEditedByUser: true
        )

        // 复制路径与 MealRecordDetailView.copyMeal 相同：重建 id、保留营养与元数据。
        let copiedFoods = original.recognizedFoods.map { food in
            MealFoodItem(
                id: UUID().uuidString,
                name: food.name,
                calories: food.calories,
                proteinGrams: food.proteinGrams,
                carbohydrateGrams: food.carbohydrateGrams,
                fatGrams: food.fatGrams,
                fiberGrams: food.fiberGrams,
                servingAmount: food.servingAmount,
                servingUnit: food.servingUnit,
                confidence: food.confidence,
                nutritionSource: food.nutritionSource,
                wasEditedByUser: food.wasEditedByUser
            )
        }
        let copy = MealRecognitionRecord(
            id: UUID().uuidString,
            mealSlot: original.mealSlot,
            recognizedFoods: copiedFoods,
            estimatedCalories: original.estimatedCalories,
            photoFileID: nil,
            photoURL: nil,
            capturedAt: Date(),
            aiProviderID: original.aiProviderID,
            aiModel: original.aiModel,
            aiConfidence: original.aiConfidence,
            wasEditedByUser: original.wasEditedByUser
        )

        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertNotEqual(copy.recognizedFoods.first?.id, original.recognizedFoods.first?.id)
        XCTAssertEqual(copy.recognizedFoods.first?.calories, 248)
        XCTAssertEqual(copy.recognizedFoods.first?.proteinGrams, 46)
        XCTAssertEqual(copy.recognizedFoods.first?.servingAmount, 150)
        XCTAssertEqual(copy.recognizedFoods.first?.nutritionSource, .aiEstimate)
        XCTAssertTrue(copy.wasEditedByUser)
        XCTAssertEqual(copy.nutritionSummary.calories, original.nutritionSummary.calories)
    }
}
