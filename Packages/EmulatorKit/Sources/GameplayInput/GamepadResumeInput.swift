import EmulationCore

public struct GamepadResumeInput: Sendable {
    private var previous = EmulatorInputState()
    private var consumesA = false
    private var consumesB = false
    private var consumesStart = false
    private var consumesSelect = false

    public init() {}

    public mutating func update(
        _ input: EmulatorInputState, canResume: Bool
    ) -> (input: EmulatorInputState, shouldResume: Bool) {
        let shouldResume = canResume && ((input.a && !previous.a) || (input.b && !previous.b)
            || (input.start && !previous.start) || (input.select && !previous.select))
        previous = input
        consumesA = input.a && (consumesA || shouldResume)
        consumesB = input.b && (consumesB || shouldResume)
        consumesStart = input.start && (consumesStart || shouldResume)
        consumesSelect = input.select && (consumesSelect || shouldResume)
        var forwarded = input
        forwarded.a = input.a && !consumesA
        forwarded.b = input.b && !consumesB
        forwarded.start = input.start && !consumesStart
        forwarded.select = input.select && !consumesSelect
        return (forwarded, shouldResume)
    }
}
