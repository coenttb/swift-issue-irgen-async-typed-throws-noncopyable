# Swift IRGen Crash: Async + Typed Throws + Nested Types + ~Copyable

## Description

The Swift compiler crashes with signal 11 during IR generation when an async function uses typed throws with a nested error type under a generic with an inverse constraint (`~Copyable`).

## Environment

- **Swift version**: 6.2.3 (swiftlang-6.2.3.3.21 clang-1700.6.3.2)
- **Target**: arm64-apple-macosx26.0
- **Crash location**: `swift::irgen::emitAsyncReturn`

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
git clone https://github.com/coenttb/swift-issue-irgen-async-typed-throws-noncopyable
cd swift-issue-irgen-async-typed-throws-noncopyable
swift build
```

## Crash Output

```
error: compile command failed due to signal 11 (use -v to see invocation)
Please submit a bug report (https://swift.org/contributing/#reporting-bugs) and include the crash backtrace.
Stack dump:
0.  Program arguments: swift-frontend -frontend -c ...
1.  Apple Swift version 6.2.3 (swiftlang-6.2.3.3.21 clang-1700.6.3.2)
2.  Compiling with the current language version
3.  While evaluating request IRGenRequest(IR Generation for file "...")
4.  While emitting IR SIL function "@$s10IRGenCrash9ContainerOAARi_zrlE7acquireAcARi_zrlE2IDVyx_GyYaAcARi_zrlE5ErrorOyx_GYKFZ".
 for 'acquire()' (at .../Crash.swift:40:12)
...
4  swift-frontend  swift::irgen::emitAsyncReturn(...) + 904
```

## Conditions Required

All four conditions must be present to trigger the crash:

| Condition | Description |
|-----------|-------------|
| 1. Generic with inverse constraint | `Container<Resource: ~Copyable>` |
| 2. Nested error type under generic | `Container.Error` in `throws(Error)` |
| 3. Async function | `async` keyword |
| 4. Typed throws | `throws(Error)` syntax |

## Isolation Tests

The reproduction includes tests to isolate the exact trigger:

```swift
// ❌ CRASHES: Nested error only (top-level return type)
public static func acquireNestedErrorOnly() async throws(Error) -> TopLevelID

// ✅ WORKS: Nested return only (top-level error type)
public static func acquireNestedReturnOnly() async throws(TopLevelError) -> ID

// ✅ WORKS: Sync function with nested types
public static func acquireSync() throws(Error) -> ID

// ✅ WORKS: Async with untyped throws
public static func acquireUntyped() async throws -> ID

// ✅ WORKS: No ~Copyable constraint
public enum RegularContainer<Resource> {
    public static func acquire() async throws(Error) -> ID
}

// ✅ WORKS: Typealiases to hoisted types
public typealias Error = HoistedError  // defined at top level
public static func acquire() async throws(Error) -> ID
```

**Key finding**: The crash is triggered specifically by the **nested error type** in the typed throws position, not the return type.

## Analysis

The crash occurs in `swift::irgen::emitAsyncReturn` during IR emission. The mangled name shows the inverse generic requirement marker (`ABRi_zrl`) appearing in both the error and return type positions:

```
@$s10IRGenCrash9ContainerOAARi_zrlE7acquireAcARi_zrlE2IDVyx_GyYaAcARi_zrlE5ErrorOyx_GYKFZ
                          ^^^^^^^^                ^^^^^^^^                    ^^^^^^^^
                          inverse                 inverse                     inverse
                          requirement             requirement                 requirement
```

The issue appears to be in how IRGen handles metadata paths for nested types under inverse generic constraints when emitting async return sequences for typed throws.

## Workaround

Hoist error types to top-level and re-export via typealiases:

```swift
// Hoisted (not nested under generic)
public enum PoolError: Swift.Error, Sendable {
    case shutdown
}

public enum Container<Resource: ~Copyable> {
    public typealias Error = PoolError  // Re-export for API consistency
}

extension Container where Resource: ~Copyable {
    // ✅ WORKS: Typealias avoids the crash
    public static func acquire() async throws(Error) -> ID {
        ID(0)
    }
}
```

## Related Issues

This appears related to the broader class of typed-throws IRGen crashes:

- [#77297](https://github.com/swiftlang/swift/issues/77297) - Typed throws with nested generic type crashes compiler
- [#83011](https://github.com/swiftlang/swift/issues/83011) - Async typed throws in generic context crashes compiler

The distinguishing factor here is the **inverse generic constraint** (`~Copyable`) which adds additional complexity to the type metadata paths.

## Impact

This bug blocks adoption of typed throws in libraries that:
- Use `~Copyable` generics (resource management, ownership patterns)
- Define domain-specific error types as nested types (common Swift pattern)
- Use async APIs (modern Swift concurrency)

This combination is common in I/O and resource management libraries where typed throws would provide significant API ergonomics benefits.
