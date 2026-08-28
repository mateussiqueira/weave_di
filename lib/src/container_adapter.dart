import 'dart:async';

import 'container.dart';

enum _Lifetime { singleton, transient, lazy }

/// Implementação do container de DI.
///
/// Essa é a classe que você vai usar no dia a dia. Suporta todos os
/// tipos de binding, scopes, override pra testes, e detecção de
/// dependências circulares.
class WeaveContainerAdapter implements WeaveContainer {
  WeaveContainerAdapter({this.name = 'default'});

  /// Instância global padrão.
  static final WeaveContainerAdapter global = WeaveContainerAdapter(name: 'global');

  /// Cria uma nova instância do container.
  static WeaveContainerAdapter create({String name = 'default'}) =>
      WeaveContainerAdapter(name: name);

  @override
  final String name;

  final Map<Type, _Binding> _registrations = {};
  final Map<Type, _Binding> _overrides = {};
  final List<WeaveContainerAdapter> _scopes = [];
  WeaveContainerAdapter? _parent;
  final Set<Type> _resolutionStack = {};
  void Function()? _onDispose;

  void _log(String message) {
    // ignore: avoid_print
    print('[Weave:$name] $message');
  }

  @override
  void bind<T>(WeaveFactory<T> factory) {
    _registrations[T] = _Binding<T>._single(factory, _Lifetime.transient);
  }

  @override
  void bindSingleton<T>(WeaveFactory<T> factory) {
    _registrations[T] = _Binding<T>._single(factory, _Lifetime.singleton);
  }

  @override
  void bindLazy<T>(WeaveFactory<T> factory) {
    _registrations[T] = _Binding<T>._single(factory, _Lifetime.lazy);
  }

  @override
  void bindInstance<T>(T instance) {
    _registrations[T] = _Binding<T>._single(
      () => instance,
      _Lifetime.singleton,
    );
  }

  @override
  void bindFactory<T, A>(WeaveFactory1<T, A> factory) {
    _registrations[T] = _Binding<T>._withArgs1(
      (arg) => factory(arg as A),
      _Lifetime.transient,
    );
  }

  @override
  void bindFactory2<T, A, B>(WeaveFactory2<T, A, B> factory) {
    _registrations[T] = _Binding<T>._withArgs2(
      (a, b) => factory(a as A, b as B),
      _Lifetime.transient,
    );
  }

  @override
  void bindFactory3<T, A, B, C>(WeaveFactory3<T, A, B, C> factory) {
    _registrations[T] = _Binding<T>._withArgs3(
      (a, b, c) => factory(a as A, b as B, c as C),
      _Lifetime.transient,
    );
  }

  @override
  Future<void> bindSingletonAsync<T>(WeaveAsyncFactory<T> factory) async {
    final instance = await factory();
    _registrations[T] = _Binding<T>._single(
      () => instance,
      _Lifetime.singleton,
    );
  }

  @override
  T get<T>() {
    if (_resolutionStack.contains(T)) {
      final cycle = _resolutionStack.toList()..add(T);
      _resolutionStack.clear();
      throw StateError(
        'Circular dependency detected: ${cycle.join(' -> ')}',
      );
    }

    _resolutionStack.add(T);
    try {
      final reg = _overrides[T] ?? _registrations[T];
      if (reg == null && _parent != null) return _parent!.get<T>();
      if (reg == null) {
        throw StateError(
          'No registration found for $T in container "$name".',
        );
      }
      final result = reg.resolve0() as T;
      _log('Resolved $T');
      return result;
    } finally {
      _resolutionStack.remove(T);
    }
  }

  @override
  T get1<T, A>(A arg) {
    final reg = _overrides[T] ?? _registrations[T];
    if (reg == null && _parent != null) return _parent!.get1<T, A>(arg);
    if (reg == null) {
      throw StateError(
        'No factory registration found for $T in container "$name".',
      );
    }
    return reg.resolve1(arg) as T;
  }

  @override
  T get2<T, A, B>(A a, B b) {
    final reg = _overrides[T] ?? _registrations[T];
    if (reg == null && _parent != null) return _parent!.get2<T, A, B>(a, b);
    if (reg == null) {
      throw StateError(
        'No factory registration found for $T in container "$name".',
      );
    }
    return reg.resolve2(a, b) as T;
  }

  @override
  T get3<T, A, B, C>(A a, B b, C c) {
    final reg = _overrides[T] ?? _registrations[T];
    if (reg == null && _parent != null) {
      return _parent!.get3<T, A, B, C>(a, b, c);
    }
    if (reg == null) {
      throw StateError(
        'No factory registration found for $T in container "$name".',
      );
    }
    return reg.resolve3(a, b, c) as T;
  }

  @override
  T? tryGet<T>() {
    try {
      return get<T>();
    } catch (_) {
      return null;
    }
  }

  @override
  void unbind<T>() {
    _registrations.remove(T);
  }

  @override
  bool isRegistered<T>() => _registrations.containsKey(T);

  @override
  void overrideFactory<T>(WeaveFactory<T> factory, {bool singleton = true}) {
    _overrides[T] = _Binding<T>._single(
      factory,
      singleton ? _Lifetime.singleton : _Lifetime.transient,
    );
  }

  @override
  void resetOverrides() {
    _overrides.clear();
  }

  @override
  WeaveContainer createScope({void Function()? onDispose}) {
    final scope = WeaveContainerAdapter(name: '$name.scope${_scopes.length}');
    scope._parent = this;
    scope._onDispose = onDispose;
    _scopes.add(scope);
    _log('Created scope: ${scope.name}');
    return scope;
  }

  @override
  void disposeScope(WeaveContainer scope) {
    if (scope is WeaveContainerAdapter) {
      scope._onDispose?.call();
      scope._registrations.clear();
      scope._overrides.clear();
      scope._parent = null;
      _scopes.remove(scope);
      _log('Disposed scope: ${scope.name}');
    }
  }

  @override
  void reset() {
    _registrations.clear();
    _overrides.clear();
    for (final scope in _scopes) {
      scope._registrations.clear();
      scope._overrides.clear();
      scope._parent = null;
    }
    _scopes.clear();
    _log('Reset');
  }

  @override
  void resetSingletons() {
    for (final reg in _registrations.values) {
      reg.resetInstance();
    }
    _log('Reset singletons');
  }

  @override
  Future<void> initializeAsync(
    List<Future<void> Function(WeaveContainer container)> initializers,
  ) async {
    for (final init in initializers) {
      await init(this);
    }
    _log('Async initialization complete (${initializers.length})');
  }
}

/// Representação interna de um binding.
///
/// Usa `Function?` porque o Dart não tem reified generics em runtime.
/// As factories são capturadas em closures que preservam o tipo.
class _Binding<T> {
  final _Lifetime _lifetime;

  /// Factory sem parâmetros.
  final Function? _factory0;

  /// Factory com 1 parâmetro.
  final Function? _factory1;

  /// Factory com 2 parâmetros.
  final Function? _factory2;

  /// Factory com 3 parâmetros.
  final Function? _factory3;

  /// Cache para singletons e lazy.
  T? _instance;
  bool _initialized = false;

  _Binding._single(Function factory, this._lifetime)
      : _factory0 = factory,
        _factory1 = null,
        _factory2 = null,
        _factory3 = null;

  _Binding._withArgs1(Function factory, this._lifetime)
      : _factory0 = null,
        _factory1 = factory,
        _factory2 = null,
        _factory3 = null;

  _Binding._withArgs2(Function factory, this._lifetime)
      : _factory0 = null,
        _factory1 = null,
        _factory2 = factory,
        _factory3 = null;

  _Binding._withArgs3(Function factory, this._lifetime)
      : _factory0 = null,
        _factory1 = null,
        _factory2 = null,
        _factory3 = factory;

  bool get _shouldCache =>
      _lifetime == _Lifetime.singleton || _lifetime == _Lifetime.lazy;

  dynamic resolve0() {
    if (_shouldCache) {
      if (!_initialized) {
        _instance = (_factory0 as WeaveFactory<T>)();
        _initialized = true;
      }
      return _instance!;
    }
    return (_factory0 as WeaveFactory<T>)();
  }

  dynamic resolve1(dynamic arg) {
    if (_shouldCache) {
      if (!_initialized) {
        // ignore: avoid_dynamic_calls
        _instance = _factory1!(arg) as T;
        _initialized = true;
      }
      return _instance!;
    }
    // ignore: avoid_dynamic_calls
    return _factory1!(arg) as T;
  }

  dynamic resolve2(dynamic a, dynamic b) {
    if (_shouldCache) {
      if (!_initialized) {
        // ignore: avoid_dynamic_calls
        _instance = _factory2!(a, b) as T;
        _initialized = true;
      }
      return _instance!;
    }
    // ignore: avoid_dynamic_calls
    return _factory2!(a, b) as T;
  }

  dynamic resolve3(dynamic a, dynamic b, dynamic c) {
    if (_shouldCache) {
      if (!_initialized) {
        // ignore: avoid_dynamic_calls
        _instance = _factory3!(a, b, c) as T;
        _initialized = true;
      }
      return _instance!;
    }
    // ignore: avoid_dynamic_calls
    return _factory3!(a, b, c) as T;
  }

  void resetInstance() {
    _instance = null;
    _initialized = false;
  }

  bool get isInitialized => _initialized;
}
