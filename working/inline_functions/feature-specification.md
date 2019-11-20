# Inline functions

## Declaration

Inlined functions are normal function declarations which are preceded by the
`inline` keyword, for example:

```dart
inline int get five => 5;
inline int five() => 5;
```

They are valid everywhere that const functions are valid.

## Semantics

Inline function invocations are directly replaced with the body of the inline
function body, so in the example above invocations of the top level function
`five()` would be _replaced_ with the integer literal `5`.

Control flow statements such as `return`, `break`, and `continue` are allowed,
and they affect the control flow at the point where they are inlined.

  - Fat arrow syntax (`=>`) is allowed for brevity but is not treated as a
    return, and it is equivalent to `{expr}`.

The return type of an inline function is the type of the expression represented
by the body of the inline function. In the majority of cases it is expected
that the type would be `void`, but any type is allowed.

If an inline function body is a `block` expression, then the static invocation
expression must also be treated as a `block` expression, and the return type
must be `void`.

  - This likely needs further refinement - does it introduce another ambiguity
    similar to MapOrSetLiteral but much more prevalent? At parse time you can't
    know if a static invocation is for an inline function or not.

These semantics impose similar restrictions to const function invocations:

- Only static invocations are allowed on inline functions
- Generic type variables are only allowed from const function bodies
- Inline functions cannot be used as tearoffs
- Return statements are not allowed in inline functions (although they may
  be allowed in the future, and would probably represent a non-local return).

## Motivating use cases

### assert

You should be able to create the function
`assert(bool condition, String message)` such that it retains the following
properties:

- The expression for `message` is not evaluated at all if `condition` evaluates
  to `true`.
- You should be able to compile out the function entirely based on other
  constants or constant functions.

This can be implemented as a simple _inline_ function, like this:

```dart
inline void assert(bool condition, String message) {
  if (bool.fromEnvironment('ENABLE_ASSERTS', defaultValue: true)) {
    if (!condition) {
        throw AssertionError(message);
    }
  }
}
```

This would be similarly useful for logging apis which can allow for compiling
out log calls below the current log level.
