# Swift IRGen Crash: Async + Typed Throws + Nested Types + ~Copyable

## Description

The Swift compiler crashes with signal 11 during IR generation when an async function uses typed throws with a nested error type under a generic with an inverse constraint (`~Copyable`).

## Environment

- Swift 6.2 (development snapshot)
- macOS 26
- Crash occurs in `swift::irgen::emitAsyncReturn`

## Minimal Reproduction

```swift
public enum Container<Resource: ~Copyable> {}

extension Container where Resource: ~Copyable {
    public enum Error: Swift.Error, Sendable {
        case shutdown
    }

    public struct ID: Hashable, Sendable {
        public let value: Int
    }
}

extension Container where Resource: ~Copyable {
    // THIS CRASHES THE COMPILER
    public static func acquire() async throws(Error) -> ID {
        ID(0)
    }
}
```

## To Reproduce

```bash
git clone <this-repo>
cd swift-issue-irgen-async-typed-throws-noncopyable
swift build
```

## Crash Output

```
error: compile command failed due to signal 11 (use -v to see invocation)
<unknown>:0: error: LLVM ERROR: null operand!
Please file a bug report at https://github.com/swiftlang/swift and include the crash backtrace.
Stack dump:
...
While emitting IR SIL function "@$s10IRGenCrash9ContainerOAARi_zrlE7acquireAcARi_zrlE2IDVyx_GyYaAcARi_zrlE5ErrorOyx_GYKFZ"
for 'acquire()' (at /Users/.../Crash.swift:40:12)
```

## Conditions Required

All four conditions must be present to trigger the crash:

| Condition | Description |
|-----------|-------------|
| 1. Generic with inverse constraint | `Container<Resource: ~Copyable>` |
| 2. Nested types under generic | `Container.Error`, `Container.ID` |
| 3. Async function | `async` |
| 4. Typed throws with nested error | `throws(Error)` |

## Proof: Removing Any Condition Prevents Crash

```swift
// ✅ WORKS: Sync function (no async)
public static func acquireSync() throws(Error) -> ID { ID(0) }

// ✅ WORKS: Untyped throws
public static func acquireUntyped() async throws -> ID { ID(0) }

// ✅ WORKS: No ~Copyable constraint
public enum RegularContainer<Resource> {
    public enum Error: Swift.Error { case shutdown }
    public static func acquire() async throws(Error) -> ID { ... }
}

// ✅ WORKS: Non-nested types
public enum TopLevelError: Swift.Error { case shutdown }
extension Container {
    public static func acquireTopLevel() async throws(TopLevelError) -> TopLevelID { ... }
}
```

## Analysis

The crash occurs in `swift::irgen::emitAsyncReturn` when the compiler attempts to emit IR for an async function that:
- Returns a nested type (`Container<Resource>.ID`)
- Throws a nested type (`Container<Resource>.Error`)
- Where `Resource` has an inverse constraint (`~Copyable`)

The issue appears to be in how the compiler handles the combination of:
1. Async coroutine lowering
2. Typed error type metadata
3. Nested type substitution under inverse generic constraints

## Workarounds

1. **Use untyped throws**: Replace `throws(Error)` with `throws`
2. **Make function synchronous**: Remove `async`
3. **Hoist nested types to top-level**: Define `Error` and `ID` outside the generic
4. **Remove ~Copyable constraint**: Use regular `Copyable` resources

## Impact

This bug blocks adoption of typed throws in any library that:
- Uses `~Copyable` generics (common in resource management)
- Defines domain-specific error types as nested types (common pattern)
- Uses async APIs (modern Swift concurrency)

This is a significant limitation for resource management libraries that want to use Swift 6's typed throws feature with noncopyable types.
