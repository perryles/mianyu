import Foundation

/// 云端和本地视觉模型共用同一结构化校验；先兼容模型常见的 JSON 包装差异，再执行安全边界检查。
nonisolated enum AIMealStructuredResponseDecoder {
    private static let maximumPayloadBytes = 512 * 1_024
    private static let maximumFoodCount = 20
    private static let maximumFoodNameCharacters = 80
    private static let maximumPrimaryNameCharacters = 120
    private static let maximumWarningCount = 5
    private static let maximumWarningCharacters = 160

    static func decode(
        _ data: Data,
        provider: AIProviderID,
        model: String
    ) throws -> AIMealAnalysisResult {
        guard !data.isEmpty,
              data.count <= maximumPayloadBytes,
              let normalizedPayload = normalizedPayload(from: data) else {
            print("[MealDebug] normalizedPayload failed")
            throw AIMealAnalysisError.invalidStructuredResponse
        }
        let payload: AIMealProviderPayload
        do {
            payload = try JSONDecoder().decode(AIMealProviderPayload.self, from: normalizedPayload.data)
        } catch {
            print("[MealDebug] payload decode failed: \(error)")
            throw AIMealAnalysisError.invalidStructuredResponse
        }
        print("[MealDebug] status=\(payload.status ?? "nil") foods=\(payload.foods.count) rootConf=\(payload.confidence?.value ?? -1) rootConfReqNorm=\(payload.confidence?.requiredNormalization ?? false) kcal=\(payload.estimatedCalories?.value ?? -1)")

        let status = normalizedStatus(payload.status, hasFoods: !payload.foods.isEmpty)
        if status == "abstained" {
            guard payload.foods.isEmpty else {
                throw AIMealAnalysisError.invalidStructuredResponse
            }
            throw AIMealAnalysisError.abstained(
                boundedNonBlankMealValue(payload.reason, limit: 240)
            )
        }
        guard status == "recognized" || status == "needs_review" else {
            throw AIMealAnalysisError.invalidStructuredResponse
        }

        guard (1...maximumFoodCount).contains(payload.foods.count) else {
            throw AIMealAnalysisError.invalidStructuredResponse
        }
        var normalizedScalar = normalizedPayload.requiresReview
        let foods = try payload.foods.map { food -> AIMealFoodEstimate in
            guard let name = boundedNonBlankMealValue(
                food.name,
                limit: maximumFoodNameCharacters,
                rejectOverflow: true
            ),
            let calories = food.calories?.value,
            (0...5_000).contains(calories),
            isValidConfidence(food.confidence?.value) else {
                throw AIMealAnalysisError.invalidStructuredResponse
            }
            normalizedScalar = normalizedScalar
                || food.calories?.requiredNormalization == true
                || food.confidence?.requiredNormalization == true
            let amount = validOptionalNutrient(food.estimatedAmount?.value, upperBound: 10_000)
            let protein = validOptionalNutrient(food.proteinGrams?.value, upperBound: 2_000)
            let carbohydrate = validOptionalNutrient(food.carbohydrateGrams?.value, upperBound: 2_000)
            let fat = validOptionalNutrient(food.fatGrams?.value, upperBound: 2_000)
            let fiber = validOptionalNutrient(food.fiberGrams?.value, upperBound: 1_000)
            guard amount.isValid, protein.isValid, carbohydrate.isValid, fat.isValid, fiber.isValid else {
                throw AIMealAnalysisError.invalidStructuredResponse
            }
            return AIMealFoodEstimate(
                name: name,
                calories: calories,
                confidence: food.confidence?.value,
                estimatedAmount: amount.value,
                unit: boundedNonBlankMealValue(food.unit, limit: 8),
                proteinGrams: protein.value,
                carbohydrateGrams: carbohydrate.value,
                fatGrams: fat.value,
                fiberGrams: fiber.value
            )
        }

        guard isValidConfidence(payload.confidence?.value) else {
            throw AIMealAnalysisError.invalidStructuredResponse
        }
        let confidence = payload.confidence?.value ?? 0
        let primaryName = boundedNonBlankMealValue(
            payload.primaryName,
            limit: maximumPrimaryNameCharacters,
            rejectOverflow: true
        )
            ?? foods.prefix(3).map(\.name).joined(separator: "、")
        let warnings = Array((payload.warnings ?? []).compactMap {
            boundedNonBlankMealValue($0, limit: maximumWarningCharacters)
        }.prefix(maximumWarningCount))
        let computedCalories = foods.reduce(0) { $0 + $1.calories }
        let totalMismatch: Bool
        if let reportedCalories = payload.estimatedCalories?.value {
            guard (0...100_000).contains(reportedCalories) else {
                throw AIMealAnalysisError.invalidStructuredResponse
            }
            totalMismatch = reportedCalories != computedCalories
            normalizedScalar = normalizedScalar || payload.estimatedCalories?.requiredNormalization == true
        } else {
            totalMismatch = false
        }
        normalizedScalar = normalizedScalar || payload.confidence?.requiredNormalization == true

        return AIMealAnalysisResult(
            primaryName: primaryName,
            foods: foods,
            estimatedCalories: computedCalories,
            confidence: confidence,
            requiresReview: status != "recognized" || confidence < 0.8 || totalMismatch || normalizedScalar,
            warnings: warnings,
            provider: provider,
            model: String(model.prefix(80))
        )
    }

    private static func normalizedStatus(_ value: String?, hasFoods: Bool) -> String {
        let status = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_") ?? ""

        switch status {
        case "recognized", "已识别", "识别成功", "成功":
            return "recognized"
        case "needs_review", "needsreview", "review", "success", "ok", "需确认", "需要确认", "待确认":
            return hasFoods ? "needs_review" : ""
        case "abstained", "abstain", "unable", "no_food", "not_food", "无法识别", "未识别", "非餐食":
            return "abstained"
        case "" where hasFoods:
            return "needs_review"
        default:
            return ""
        }
    }

    private static func validOptionalNutrient(_ value: Double?, upperBound: Double) -> (isValid: Bool, value: Double?) {
        guard let value else { return (true, nil) }
        return (value.isFinite && (0...upperBound).contains(value), value)
    }

    private static func normalizedPayload(from data: Data) -> NormalizedMealPayload? {
        if let object = try? JSONSerialization.jsonObject(with: data),
           let normalized = normalizedMealObject(object),
           let normalizedData = try? JSONSerialization.data(withJSONObject: normalized) {
            return NormalizedMealPayload(data: normalizedData, requiresReview: false)
        }

        guard let text = String(data: data, encoding: .utf8) else { return nil }
        if let objectData = firstJSONObjectData(in: text),
           let object = try? JSONSerialization.jsonObject(with: objectData),
           let normalized = normalizedMealObject(object),
           let normalizedData = try? JSONSerialization.data(withJSONObject: normalized) {
            return NormalizedMealPayload(data: normalizedData, requiresReview: false)
        }

        // Qwen 可能已输出完必需字段，却在多余扩展字段中耗尽令牌预算。
        guard let recoveredData = recoverableJSONObjectPrefixData(in: text),
              let object = try? JSONSerialization.jsonObject(with: recoveredData),
              let normalized = normalizedMealObject(object),
              let normalizedData = try? JSONSerialization.data(withJSONObject: normalized) else {
            return nil
        }
        return NormalizedMealPayload(data: normalizedData, requiresReview: true)
    }

    private static func normalizedMealObject(_ object: Any) -> [String: Any]? {
        if let text = object as? String,
           let nestedData = firstJSONObjectData(in: text),
           let nestedObject = try? JSONSerialization.jsonObject(with: nestedData) {
            return normalizedMealObject(nestedObject)
        }

        guard let dictionary = object as? [String: Any] else { return nil }
        let normalizedKeys = Set(dictionary.keys.map(normalizedJSONKey))
        let mealFieldKeys: Set<String> = [
            "foods", "fooditems", "foodlist", "fooddetails", "recognizedfoods", "items", "dishes",
            "食物", "食物列表", "食物明细", "菜品", "菜品列表"
        ]

        if normalizedKeys.isDisjoint(with: mealFieldKeys) {
            let wrapperKeys: Set<String> = [
                "result", "data", "meal", "analysis", "mealanalysis", "output",
                "结果", "识别结果", "餐食", "餐食分析"
            ]
            for (key, value) in dictionary where wrapperKeys.contains(normalizedJSONKey(key)) {
                if let nested = normalizedMealObject(value) { return nested }
            }
        }

        var normalized: [String: Any] = [:]
        for (key, value) in dictionary {
            switch normalizedJSONKey(key) {
            case "status", "recognitionstatus", "状态", "识别状态":
                normalized["status"] = value
            case "primaryname", "mealname", "dishname", "name", "餐食名称", "菜品名称", "名称":
                normalized["primaryName"] = value
            case "confidence", "score", "置信度", "可信度":
                normalized["confidence"] = value
            case "estimatedcalories", "totalcalories", "totalcalorie", "calories", "kcal", "总热量", "估算热量", "热量":
                normalized["estimatedCalories"] = value
            case "foods", "fooditems", "foodlist", "fooddetails", "recognizedfoods", "items", "dishes", "食物", "食物列表", "食物明细", "菜品", "菜品列表":
                normalized["foods"] = normalizedFoods(value)
            case "warnings", "warning", "alerts", "提示", "警告":
                normalized["warnings"] = normalizedWarnings(value)
            case "reason", "message", "description", "原因", "说明":
                normalized["reason"] = value
            default:
                continue
            }
        }
        return normalized
    }

    private static func normalizedFoods(_ value: Any) -> Any {
        if let foodMap = value as? [String: Any] {
            return foodMap.map { name, calories in
                ["name": name, "calories": calories]
            }
        }
        guard let foods = value as? [Any] else { return value }
        return foods.map { item -> Any in
            guard let food = item as? [String: Any] else { return item }
            var normalized: [String: Any] = [:]
            for (key, value) in food {
                switch normalizedJSONKey(key) {
                case "name", "foodname", "dishname", "label", "food", "dish", "item", "食物", "食物名称", "菜品", "菜名", "名称":
                    normalized["name"] = value
                case "calories", "calorie", "estimatedcalories", "calorieestimate", "estimatedkcal", "kcal", "热量", "卡路里", "估算热量":
                    normalized["calories"] = value
                case "confidence", "score", "probability", "置信度", "可信度":
                    normalized["confidence"] = value
                case "estimatedamount", "amount", "weight", "weightgrams", "portion", "估算份量", "份量", "重量": normalized["estimatedAmount"] = value
                case "unit", "单位": normalized["unit"] = value
                case "protein", "proteingrams", "蛋白质": normalized["proteinGrams"] = value
                case "carbohydrate", "carbohydrates", "carbs", "carbohydrategrams", "碳水": normalized["carbohydrateGrams"] = value
                case "fat", "fatgrams", "脂肪": normalized["fatGrams"] = value
                case "fiber", "fibergrams", "膳食纤维", "纤维": normalized["fiberGrams"] = value
                default:
                    continue
                }
            }
            return normalized
        }
    }

    private static func normalizedWarnings(_ value: Any) -> Any {
        if let warning = value as? String { return [warning] }
        return value
    }

    private static func normalizedJSONKey(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// 提取说明文字或 Markdown 代码围栏中的第一个完整 JSON 对象，同时正确跳过字符串内的大括号。
    private static func firstJSONObjectData(in text: String) -> Data? {
        var startIndex: String.Index?
        var depth = 0
        var isInsideString = false
        var isEscaping = false

        for index in text.indices {
            let character = text[index]
            if startIndex == nil {
                guard character == "{" else { continue }
                startIndex = index
                depth = 1
                continue
            }

            if isInsideString {
                if isEscaping {
                    isEscaping = false
                } else if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    isInsideString = false
                }
                continue
            }

            switch character {
            case "\"":
                isInsideString = true
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0, let startIndex {
                    return String(text[startIndex...index]).data(using: .utf8)
                }
            default:
                continue
            }
        }
        return nil
    }

    /// 仅在顶层字段完整结束的位置闭合被截断的根对象。
    /// 排除嵌套逗号，避免把不完整的食物或警告内容误判为完整输入。
    private static func recoverableJSONObjectPrefixData(in text: String) -> Data? {
        var startIndex: String.Index?
        var objectDepth = 0
        var arrayDepth = 0
        var isInsideString = false
        var isEscaping = false
        var topLevelCommas: [String.Index] = []

        for index in text.indices {
            let character = text[index]
            if startIndex == nil {
                guard character == "{" else { continue }
                startIndex = index
                objectDepth = 1
                continue
            }

            if isInsideString {
                if isEscaping {
                    isEscaping = false
                } else if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    isInsideString = false
                }
                continue
            }

            switch character {
            case "\"":
                isInsideString = true
            case "{":
                objectDepth += 1
            case "}":
                objectDepth -= 1
            case "[":
                arrayDepth += 1
            case "]":
                arrayDepth -= 1
            case "," where objectDepth == 1 && arrayDepth == 0:
                topLevelCommas.append(index)
            default:
                continue
            }
        }

        guard let startIndex else { return nil }
        for comma in topLevelCommas.reversed() {
            let candidate = String(text[startIndex..<comma]) + "}"
            guard let candidateData = candidate.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: candidateData)) != nil else {
                continue
            }
            return candidateData
        }
        return nil
    }
}

nonisolated private struct NormalizedMealPayload {
    let data: Data
    let requiresReview: Bool
}

nonisolated private struct AIMealProviderPayload: Decodable, Sendable {
    let status: String?
    let primaryName: String?
    let confidence: FlexibleMealConfidence?
    let estimatedCalories: FlexibleMealInteger?
    let foods: [Food]
    let warnings: [String]?
    let reason: String?

    struct Food: Decodable, Sendable {
        let name: String?
        let calories: FlexibleMealInteger?
        let confidence: FlexibleMealConfidence?
        let estimatedAmount: FlexibleMealDouble?
        let unit: String?
        let proteinGrams: FlexibleMealDouble?
        let carbohydrateGrams: FlexibleMealDouble?
        let fatGrams: FlexibleMealDouble?
        let fiberGrams: FlexibleMealDouble?
    }
}

nonisolated private struct FlexibleMealInteger: Decodable, Sendable {
    let value: Int
    let requiredNormalization: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let integer = try? container.decode(Int.self) {
            value = integer
            requiredNormalization = false
            return
        }

        let number: Double
        if let double = try? container.decode(Double.self) {
            number = double
            requiredNormalization = false
        } else {
            let text = try container.decode(String.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if let double = Double(text) {
                number = double
                requiredNormalization = false
            } else {
                guard let extracted = firstMealNumber(in: text) else {
                    throw MealScalarDecodingError.invalidNumber
                }
                number = extracted
                requiredNormalization = true
            }
        }
        guard number.isFinite,
              number >= Double(Int.min),
              number <= Double(Int.max) else {
            throw MealScalarDecodingError.invalidNumber
        }
        value = Int(number.rounded())
    }
}

nonisolated private struct FlexibleMealConfidence: Decodable, Sendable {
    let value: Double
    let requiredNormalization: Bool

    init(from decoder: Decoder) throws {
        let decoded = try FlexibleMealDouble(
            from: decoder,
            treatsValueAsPercentage: true
        )
        value = decoded.value
        requiredNormalization = decoded.requiredNormalization
    }
}

nonisolated private struct FlexibleMealDouble: Decodable, Sendable {
    let value: Double
    let requiredNormalization: Bool

    init(from decoder: Decoder) throws {
        try self.init(from: decoder, treatsValueAsPercentage: false)
    }

    /// 只有置信度类字段允许把 2-100 的数值按百分比归一（85 → 0.85）；
    /// 营养素克数（如纤维 2g）不能被当作百分比折叠。
    init(from decoder: Decoder, treatsValueAsPercentage: Bool = false) throws {
        let container = try decoder.singleValueContainer()
        let rawValue: Double
        var normalized = false
        var isExplicitPercentage = false
        if let double = try? container.decode(Double.self) {
            rawValue = double
        } else {
            let text = try container.decode(String.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if let double = Double(text) {
                rawValue = double
            } else if text.hasSuffix("%"), let percentage = firstMealNumber(in: text) {
                rawValue = percentage
                normalized = true
                isExplicitPercentage = true
            } else {
                throw MealScalarDecodingError.invalidNumber
            }
        }
        guard rawValue.isFinite else { throw MealScalarDecodingError.invalidNumber }
        if treatsValueAsPercentage, rawValue > 1, rawValue <= 100, isExplicitPercentage || rawValue >= 2 {
            value = rawValue / 100
            requiredNormalization = true
        } else {
            value = rawValue
            requiredNormalization = normalized
        }
    }
}

nonisolated private enum MealScalarDecodingError: Error {
    case invalidNumber
}

/// Qwen 偶尔会把数值写成“约 180 kcal”；只提取首个有限数字，并在上层强制人工确认。
nonisolated private func firstMealNumber(in text: String) -> Double? {
    let normalized = text.replacingOccurrences(of: ",", with: "")
    let pattern = #"[-+]?\d+(?:\.\d+)?"#
    guard let expression = try? NSRegularExpression(pattern: pattern),
          let match = expression.firstMatch(
            in: normalized,
            range: NSRange(normalized.startIndex..., in: normalized)
          ),
          let range = Range(match.range, in: normalized),
          let value = Double(normalized[range]),
          value.isFinite else {
        return nil
    }
    return value
}

nonisolated private func boundedNonBlankMealValue(
    _ value: String?,
    limit: Int,
    rejectOverflow: Bool = false
) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if rejectOverflow, trimmed.count > limit { return nil }
    return String(trimmed.prefix(limit))
}

nonisolated private func isValidConfidence(_ value: Double?) -> Bool {
    guard let value else { return true }
    return value.isFinite && (0...1).contains(value)
}
