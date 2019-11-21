# Const functions

## Goals

Expand the const grammar to allow for const functions which can run code inside
the compiler to create other const objects and return them.

This will be used as the basis for a new static metaprogramming approach based
on const reflection apis.

Ultimately the goal is to enable using reflection in a way that does not come
with any code size or performance overhead compared to the hand written
boilerplate it is replacing.

## Semantics

All invocations of a const function are _replaced_ at compile time with a
_reference_ to the actual const object that they create. The constant itself
is placed in a lookup table.

- This is to prevent infinite expansion of consts (a topic which needs some
  more exploration, this on its own does not solve the problem).

In order to enable this, the following limitations are applied to const
functions:

- Only static invocations are allowed on const functions
- All arguments (including type arguments) must be const
  - Except for invocations from other const functions
- They can only invoke const functions
- They can only read const variables
- They can only return const objects

Constants which are only used as a part of a const function body but which are
not ultimately referenced in the program _must be_ tree-shaken out. One
approach to this is to mark consts as "used" when they are returned from a
const function (including all references to other consts from the returned
constant).

- This is the **core principle** upon which the new reflection apis are based.
  It allows for const functions which can reflect deeply on the program without
  bloating the final application with all the information they saw.

## Declaration

Const functions look like normal function declarations which are preceded by
the `const` keyword.

```dart
const addOne(int original) => original + 1;
```

Const functions are allowed only where static invocations can be guaranteed, 
including:

Top level functions/getters:

```dart
const int get five => 5;
const int five() => 5;
```

Static functions/getters:

```dart
class int {
  static const get int five => 5;
  static const int five() => 5
}
```

Local functions:

```dart
void main() {
  const add(int a, int b) => a + b;

  const x = add(1, 2);
}
```

Notably, anonymous functions and instance methods are not allowed.

Additionally, const function tearoffs are not allowed.

**Note:** We may be able to relax some of these restrictions in the future.

## Reflection API

All instances of classes from `dart:mirrors` are already constructed through
one of three top level methods: `reflect`, `reflectType`, and `reflectClass`.

These functions signatures will all change to be `external const` functions,
but they _need not otherwise change_.

When a static invocation of one of these apis is encountered, kernel will
synthesize the corresponding constant for that invocation if it does not
yet exist.

## Usage Examples

### `List<Symbol> fieldNamesOf<T>()`

The only difference between the following implementation and the one which
works today is the `const` modifier on the function.

```dart
import 'dart:mirrors';

const List<Symbol> fieldNamesOf<T>() {
  var typeMirror = reflectClass(T);
  return [
    for (var d in typeMirror.declarations.values)
      if (d is VariableMirror && d.isFinal) d.simpleName,
  ];
}
```

Note that this function is itself const, which allows it to pass its type
variables down to `reflectClass(T)`.

Additionally, it can crawl all the declarations of `T`, but the only thing
that ends up in the final program is the constant list of field symbols. We
were not required to retain the other declarations or any other information
about `T` even though we "used" it during the const creation.

**Note**: This does assume well behaved uses of reflection - essentially it
assumes that nobody returns any reflection based constants from their const
functions. We could ban doing this, or we could redesign the apis to make the
classes have less information in them, and add more top level apis instead
(for instance, `declarationsOf(T)` instead of a `ClassMirror.declarations`
field).

### `Converter<String, T> jsonDecoder<T>()`

See [json-decoder-example.dart](json-decoder-example.dart) for an
implementation example of this api.
