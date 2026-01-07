# Swift IRGen Crash: Async Function with Typed Throws and Nested Error Type Under Generic

## Description

The Swift compiler crashes with signal 11 during IR generation when an async function uses typed throws with a nested error type under **any** generic type.

**Note**: This bug does NOT require `~Copyable` - any generic parameter triggers it.

## Environment

- **Swift version**: 6.2.3 (swiftlang-6.2.3.3.21 clang-1700.6.3.2)
- **Target**: arm64-apple-macosx26.0
- **Crash location**: `swift::irgen::emitAsyncReturn`

## Minimal Reproduction (4 lines)

```swift
public enum Box<T> {
    public enum Error: Swift.Error { case fail }
    public static func go() async throws(Error) {}  // CRASHES
}
```

## To Reproduce

```bash
git clone https://github.com/coenttb/swift-issue-irgen-async-typed-throws-noncopyable
cd swift-issue-irgen-async-typed-throws-noncopyable
swift build
```

Or directly:

```bash
echo 'public enum Box<T> { public enum Error: Swift.Error { case fail }; public static func go() async throws(Error) {} }' > /tmp/crash.swift
swiftc -parse-as-library -emit-ir /tmp/crash.swift
```

## Crash Output

```
error: compile command failed due to signal 11 (use -v to see invocation)
Stack dump:
0.  Program arguments: swift-frontend -frontend -emit-ir ...
1.  Apple Swift version 6.2.3 (swiftlang-6.2.3.3.21 clang-1700.6.3.2)
2.  Compiling with effective version 5.10
3.  While evaluating request IRGenRequest(IR Generation for file "...")
4.  While emitting IR SIL function "@$s6test103BoxO2goyyYaAC5ErrorOyx_GYKFZ".
 for 'go()' (at .../crash.swift:12:12)
...
4  swift-frontend  swift::irgen::emitAsyncReturn(...) + 904
```

## Conditions Required

All three conditions must be present to trigger the crash:

| Condition | Description |
|-----------|-------------|
| 1. Generic type | Any generic parameter (e.g., `Box<T>`) |
| 2. Nested error type | Error type defined inside the generic |
| 3. Async + typed throws | `async throws(NestedError)` |

## Verified Test Results

| Test | Description | Result |
|------|-------------|--------|
| Sync function | `throws(Error)` without `async` | ✅ Compiles |
| Untyped throws | `async throws` (not typed) | ✅ Compiles |
| Non-generic | `Box` without generic parameter | ✅ Compiles |
| Top-level error | `throws(TopLevelError)` | ✅ Compiles |
| Nested return only | Nested return type, top-level error | ✅ Compiles |
| Typealias workaround | `typealias Error = HoistedError` | ✅ Compiles |
| With ~Copyable | `Box<T: ~Copyable>` | ❌ Crashes (same bug) |
| Minimal generic | `Box<T>` with nested error | ❌ Crashes |

**Key finding**: The crash is triggered specifically by the **nested error type in typed throws position** under any generic. `~Copyable` is not required.

## Workaround

Hoist error types to top-level and re-export via typealiases:

```swift
// Hoisted (not nested under generic)
public enum BoxError: Swift.Error { case fail }

public enum Box<T> {
    public typealias Error = BoxError
    public static func go() async throws(Error) {}  // ✅ Works
}
```

## Related Issues

This appears related to:

- [#77297](https://github.com/swiftlang/swift/issues/77297) - Typed throws with nested generic type crashes compiler
- [#83011](https://github.com/swiftlang/swift/issues/83011) - Async typed throws in generic context crashes compiler

## Impact

This blocks adoption of typed throws in any library that:
- Uses generic types (very common)
- Defines domain-specific error types as nested types (common Swift pattern)
- Uses async APIs (modern Swift concurrency)

This is a common pattern in I/O, networking, and resource management libraries.
