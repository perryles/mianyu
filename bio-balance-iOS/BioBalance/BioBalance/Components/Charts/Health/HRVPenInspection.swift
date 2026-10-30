/// Input-local selection: leaving a pointer must not dismiss touch or VoiceOver.
nonisolated struct HRVPenInspection {
    enum Input: Equatable {
        case touch, pointer, accessibility
    }

    private(set) var index: Int?
    private(set) var lastIndex = 0
    private(set) var input: Input?

    mutating func select(_ index: Int?, input: Input) {
        guard let index, index >= 0 else { return }
        self.index = index
        lastIndex = index
        self.input = input
    }

    mutating func end(_ input: Input) {
        guard self.input == input else { return }
        index = nil
        self.input = nil
    }

    mutating func adjust(by offset: Int, count: Int) {
        guard count > 0 else {
            reset()
            return
        }
        let current = min(index ?? (count - 1), count - 1)
        select(min(max(current + offset, 0), count - 1), input: .accessibility)
    }

    mutating func reset() {
        index = nil
        lastIndex = 0
        input = nil
    }
}
