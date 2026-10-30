import Foundation

/// 手动录入的食物搜索状态。
nonisolated enum MealFoodSearchState: Equatable {
    case idle
    case searching
    case results([MealFoodItem])
    case empty
    case failure(String)

    static func == (lhs: MealFoodSearchState, rhs: MealFoodSearchState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.searching, .searching), (.empty, .empty):
            return true
        case (.results(let a), .results(let b)):
            return a.map(\.id) == b.map(\.id)
        case (.failure(let a), .failure(let b)):
            return a == b
        default:
            return false
        }
    }
}

/// 手动录入的食物营养查询服务。
///
/// 项目当前没有接入真实食品营养数据库（如 FatSecret/USDA）；按产品约束，
/// 搜索走现有 Qwen 文本通道做结构化估算，结果一律标记 `nutritionSource = .aiEstimate`，
/// UI 必须以「估算」口径展示，用户可在编辑器里修正。
nonisolated struct MealFoodSearchService {
    /// 结构化输出约束：固定字段、数量与数值边界，解码失败即视为查询失败。
    static let searchSystemPrompt = """
    你是食物营养查询助手，根据食物名称给出每 100 克或每常见单个份量的营养估算。
    不做医疗建议，不推断用户健康状况。无法判断的食物返回空数组。
    输出必须是单个 JSON 对象：{"items":[{"name":"...","calories":整数,"servingAmount":数字或null,"unit":"g|ml|个|碗|片|杯|份","proteinGrams":数字或null,"carbohydrateGrams":数字或null,"fatGrams":数字或null,"fiberGrams":数字或null}]}
    items 最多 5 项，calories 为 0-2000 的非负整数；无法可靠估算的字段填 null，不要编造小数精度。
    """

    private let registry: AIProviderRegistry

    init(registry: AIProviderRegistry = .live()) {
        self.registry = registry
    }

    /// 按名称查询候选食物；结果为估算值，交由用户确认。
    func search(query: String) async throws -> [MealFoodItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 60 else { return [] }

        guard let provider = registry.textProvider(id: .qwen, capability: .healthChat) else {
            throw AIServiceError.disabledProvider
        }
        let request = AITextRequest(
            capability: .healthChat,
            messages: [
                .init(role: .system, content: Self.searchSystemPrompt),
                .init(role: .user, content: "查询食物：\(trimmed)")
            ]
        )
        let response = try await provider.generateText(request)
        guard let data = response.content.data(using: .utf8) else {
            throw AIServiceError.decodingFailed
        }
        return try Self.decodeItems(from: data)
    }

    /// 解析并校验搜索结果：拒绝负数、越界与非有限数值。
    nonisolated static func decodeItems(from data: Data) throws -> [MealFoodItem] {
        struct Payload: Decodable {
            struct Item: Decodable {
                let name: String?
                let calories: Int?
                let servingAmount: Double?
                let unit: String?
                let proteinGrams: Double?
                let carbohydrateGrams: Double?
                let fatGrams: Double?
                let fiberGrams: Double?
            }
            let items: [Item]?
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data), payload.items != nil else {
            throw AIServiceError.decodingFailed
        }
        let items = (payload.items ?? []).compactMap { item -> MealFoodItem? in
            guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty, name.count <= 80,
                  let calories = item.calories,
                  (0...2_000).contains(calories) else { return nil }
            func valid(_ value: Double?, upper: Double) -> Double? {
                guard let value, value.isFinite, (0...upper).contains(value) else { return nil }
                return value
            }
            return MealFoodItem(
                id: "meal-search-\(UUID().uuidString)",
                name: String(name.prefix(80)),
                calories: calories,
                proteinGrams: valid(item.proteinGrams, upper: 200),
                carbohydrateGrams: valid(item.carbohydrateGrams, upper: 200),
                fatGrams: valid(item.fatGrams, upper: 200),
                fiberGrams: valid(item.fiberGrams, upper: 100),
                servingAmount: valid(item.servingAmount, upper: 10_000),
                servingUnit: item.unit.flatMap { String($0.prefix(8)) },
                confidence: nil,
                nutritionSource: .aiEstimate,
                wasEditedByUser: false
            )
        }
        return items
    }
}
