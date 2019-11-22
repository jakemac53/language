import 'dart:convert';
import 'dart:mirrors';

class User {
  final String name;
  final int age;
  User(this.name, {this.age});

  String toString() => '$name, age ${age == null ? 'unknown' : age}';
}

void main() {
  var decoder = jsonDecoder<User>(const {
    User: Config(positionalParameterKeys: ['name'])
  });
  var user = decoder.convert('''
{
  "name": "Jake",
  "age": 123456
}
  ''');
  print(user);
}

const Converter<String, T> jsonDecoder<T>([Map<Type, Config> typeConfig]) =>
    JsonDecoder().fuse(jsonConverter<T>(typeConfig));
    // We need a const constructor for this, and a public class:
    //
    // const _FusedConverter(JsonDecoder(), jsonConverter<T>(typeConfig));

const Converter<Object, T> jsonConverter<T>(Map<Type, Config> typeConfig) {
  /// TODO: Support maps, lists, etc
  switch (T) {
    case int:
    case double:
    case num:
    case String:
      return const CastConverter<T>();
  }

  // TODO: Generics mess this up - the config map is keyed on the raw type
  // with no type arguments. Extract that same raw type from T before the
  // lookup.
  var config = typeConfig[T] ?? const Config();
  var invoker = _invokerFor<T>(config);
  var positionalArgumentConverters = [
    for (var i = 0; i < config.positionalParameterKeys.length; i++)
      // TODO: specify this syntax, possibly change it. We need to be able
      // to provide a constant Type instance as a type parameter (same
      // below for named arg converters).
      jsonConverter<invoker.method.parameters[i].type.reflectedType>(
          typeConfig)
  ];
  var namedArgumentConverters = {
    for (var param in invoker.method.parameters.where((p) => p.isNamed))
      param.simpleName:
          jsonConverter<param.type.reflectedType>(typeConfig)
  };

  return JsonConverter<T>(
      invoker, positionalArgumentConverters, namedArgumentConverters,
      config: config);
}

const Invoker<T> _invokerFor<T>(Config config) {
  if (config.factory != null) {
    var methodMirror = reflect(config.factory) as MethodMirror;
    var namedParams = [
      for (var param in methodMirror.parameters) param.simpleName
    ];
    return const FunctionInvoker<T>(
        methodMirror.owner as ObjectMirror, methodMirror, namedParams);
  }

  // TODO: Handle non-class types
  var classMirror = reflectClass(T);
  var constructorMirror = classMirror.declarations.values.firstWhere(
      (d) =>
          d is MethodMirror &&
          d.isConstructor &&
          d.simpleName == classMirror.simpleName,
      orElse: () => throw 'No unnamed constructor for $T!') as MethodMirror;

  var namedParams = [
    for (var param in constructorMirror.parameters.where((p) => p.isNamed))
      param.simpleName
  ];
  return const ConstructorInvoker<T>(classMirror, constructorMirror, namedParams);
}

class JsonConverter<T> extends Converter<Object, T> {
  final Invoker<T> _invoker;
  final Config _config;
  final List<Converter<Object, dynamic>> _positionalArgumentConverters;
  final Map<Symbol, Converter<Object, dynamic>> _namedArgumentConverters;

  const JsonConverter(this._invoker, this._positionalArgumentConverters,
      this._namedArgumentConverters,
      {Config config})
      : _config = config ?? const Config();

  @override
  T convert(Object json) {
    if (json == null) return null;

    if (_config.passRawValue) {
      return _invoker.invoke([json]);
    }
    if (json is Map<String, dynamic>) {
      var named = {
        for (var name in _invoker.namedParameters)
          name: _paramFromJson(name, json)
      };
      var positional = [
        for (var i = 0; i < (_config.positionalParameterKeys?.length ?? 0); i++)
          _positionalArgumentConverters[i]
              .convert(json[_config.positionalParameterKeys[i]])
      ];
      return _invoker.invoke(positional, named);
    }
    throw 'Unexpected json type!';
  }

  dynamic _paramFromJson(Symbol name, Map<String, dynamic> json) {
    var jsonVal = json[_keyName(name, _config.parameterKeys)];
    if (jsonVal == null) return null;
    return _namedArgumentConverters[name].convert(jsonVal);
  }
}

String _keyName(Symbol name, Map<Symbol, String> overrides) {
  var nameStr = name.toString();
  // TODO: gross! Symbols really tie our hands here. The only way to get the
  // original string value for the symbol is through this nasy hack.
  //
  // We should reconsider if symbols are providing any value here and changing
  // the mirrors apis to be string based if not.
  nameStr = nameStr.substring(8, nameStr.length - 2);
  if (overrides == null) return nameStr;
  return overrides[name] ?? nameStr;
}

class CastConverter<T> extends Converter<Object, T> {
  const CastConverter();

  @override
  T convert(Object input) => input as T;
}

/// TODO: Ideally we would not keep leak instances of any mirrors object
/// outside of the const functions but all implementations of this violate
/// that. How can we mitigate that?
///
/// TODO: We assume the MethodMirror can do efficient (static) dispatch,
/// which todays mirrors does not do. Specify exactly how that should work.
abstract class Invoker<T> {
  List<Symbol> get namedParameters;
  MethodMirror get method;

  T invoke(List<dynamic> positionalArgs, [Map<Symbol, dynamic> namedArgs]);
}

class ConstructorInvoker<T> implements Invoker<T> {
  final ClassMirror clazz;
  final MethodMirror method;

  final List<Symbol> namedParameters;

  const ConstructorInvoker(this.clazz, this.method, this.namedParameters);

  @override
  T invoke(List<dynamic> positionalArgs, [Map<Symbol, dynamic> namedArgs]) =>
      clazz.newInstance(Symbol(''), positionalArgs, namedArgs).reflectee;
}

class FunctionInvoker<T> implements Invoker<T> {
  final ObjectMirror owner;
  final MethodMirror method;
  final List<Symbol> namedParameters;

  const FunctionInvoker(this.owner, this.method, this.namedParameters);

  @override
  T invoke(List<dynamic> positionalArgs, [Map<Symbol, dynamic> namedArgs]) =>
      owner.invoke(method.simpleName, positionalArgs, namedArgs).reflectee;
}

/// Provides configuration for deserializing a certain class.
///
/// This is applied uniformly to the class and is not configurable based on its
/// type arguments.
class Config {
  /// A custom method to invoke for this type.
  final Function factory;

  /// Maps parameter names to json keys.
  final Map<Symbol, String> parameterKeys;

  /// If `true` then [constructor] must take exactly one positional argument,
  /// and the raw JSON value will be passed to it.
  final bool passRawValue;

  /// Required for invoking methods that have positional parameters.
  ///
  /// Maps the JSON key to the positional parameter at the same index.
  ///
  /// This is required because positional parameter names are not a part of the
  /// public API of a function, and depending on them would violate that
  /// contract.
  final List<String> positionalParameterKeys;

  const Config(
      {this.factory,
      this.parameterKeys,
      bool passRawValue,
      this.positionalParameterKeys})
      : passRawValue = false;
}
