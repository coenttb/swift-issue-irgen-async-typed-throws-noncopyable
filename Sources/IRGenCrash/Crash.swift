/// Minimal reproduction for Swift compiler IRGen crash.
///
/// The compiler crashes (signal 11) when all four conditions are met:
/// 1. Generic type with inverse constraint (~Copyable)
/// 2. Nested types (Error, ID) under that generic
/// 3. Async function
/// 4. Typed throws with the nested error type
///
/// Removing ANY ONE of these conditions prevents the crash.

// MARK: - Container with ~Copyable constraint

public enum Container<Resource: ~Copyable> {}

// MARK: - Nested types under ~Copyable generic

extension Container where Resource: ~Copyable {
    public enum Error: Swift.Error, Sendable {
        case shutdown
        case timeout
    }

    public struct ID: Hashable, Sendable {
        public let value: Int
        public init(_ value: Int) { self.value = value }
    }
}

// MARK: - Async function with typed throws returning nested type
// THIS CRASHES THE COMPILER

extension Container where Resource: ~Copyable {
    /// This function signature triggers the IRGen crash.
    ///
    /// The crash occurs in `swift::irgen::emitAsyncReturn` when the compiler
    /// attempts to emit IR for an async function that:
    /// - throws a nested type (Container<Resource>.Error)
    /// - returns a nested type (Container<Resource>.ID)
    /// - where Resource has an inverse constraint (~Copyable)
    public static func acquire() async throws(Error) -> ID {
        ID(0)
    }
}

// MARK: - Proof that removing any condition prevents the crash

extension Container where Resource: ~Copyable {
    // ✅ WORKS: Sync function (no async)
    public static func acquireSync() throws(Error) -> ID {
        ID(0)
    }

    // ✅ WORKS: Untyped throws
    public static func acquireUntyped() async throws -> ID {
        ID(0)
    }
}

// ✅ WORKS: No ~Copyable constraint
public enum RegularContainer<Resource> {
    public enum Error: Swift.Error, Sendable { case shutdown }
    public struct ID: Hashable, Sendable { let value: Int }

    public static func acquire() async throws(Error) -> ID {
        ID(value: 0)
    }
}

// ✅ WORKS: Non-nested types
public enum TopLevelError: Swift.Error, Sendable { case shutdown }
public struct TopLevelID: Hashable, Sendable { let value: Int }

extension Container where Resource: ~Copyable {
    public static func acquireTopLevel() async throws(TopLevelError) -> TopLevelID {
        TopLevelID(value: 0)
    }
}
