public protocol LibraryTransactionRunner: Sendable {
    func run<T: Sendable>(_ operation: @Sendable () throws -> T) throws -> T
}

public struct PassthroughTransactionRunner: LibraryTransactionRunner {
    public init() {}

    public func run<T: Sendable>(_ operation: @Sendable () throws -> T) throws -> T {
        try operation()
    }
}
