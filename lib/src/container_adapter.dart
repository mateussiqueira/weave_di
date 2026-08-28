import 'dart:async';

import 'container.dart';
import 'errors.dart';
import 'logger.dart';

enum _Lifetime { singleton, transient, eager }

/// Chave de um registro: tipo mais nome opcional.
///
/// Record em vez de classe: igualdade e hashCode estruturais de graça, que é
/// exatamente o contrato que um Map exige.
typedef _Key = (Type, Object?);

/// Implementação do container de DI.
///
/// Suporta bindings nomeados, escopos com resolução para o pai, override para
/// teste, dispose por binding e detecção de dependência circular.
class WeaveContainerAdapter implements WeaveContainer {
  // Parâmetro nomeado não pode começar com `_`, então `this._logger` não é
  // possível aqui — a sugestão do lint não se aplica.
  WeaveContainerAdapter({this.name = 'default', WeaveLogger? logger})
      // ignore: prefer_initializing_formals
      : _logger = logger;

  /// Instância global padrão.
  static final WeaveContainerAdapter global =
      WeaveContainerAdapter(name: 'global');

  /// Cria uma nova instância do container.
  static WeaveContainerAdapter create({
    String name = 'default',
    WeaveLogger? logger,
  }) =>
      WeaveContainerAdapter(name: name, logger: logger);

  @override
  final String name;

  final Map<_Key, _Binding<Object?>> _registrations = <_Key, _Binding<Object?>>{};
  final Map<_Key, _Binding<Object?>> _overrides = <_Key, _Binding<Object?>>{};
  final List<WeaveContainerAdapter> _scopes = <WeaveContainerAdapter>[];
  WeaveContainerAdapter? _parent;
  final Set<_Key> _resolutionStack = <_Key>{};
  void Function()? _onDispose;
  final WeaveLogger? _logger;

  void _log(String message) =>
      WeaveLog.write('Weave:$name', message, override: _logger);

  void _put<T>(_Key key, _Binding<Object?> binding) {
    // Rebind descarta a instância anterior, mas só depois de avisá-la.
    _registrations.remove(key)?.dispose();
    _registrations[key] = binding;
  }

  // ── Registros ─────────────────────────────────────────────────────────

  @override
  void bind<T>(WeaveFactory<T> factory, {Object? name}) =>
      _put<T>((T, name), _Binding<T>.zero(factory, _Lifetime.transient));

  @override
  void bindSingleton<T>(
    WeaveFactory<T> factory, {
    Object? name,
    WeaveDispose<T>? dispose,
  }) =>
      _put<T>(
        (T, name),
        _Binding<T>.zero(factory, _Lifetime.singleton, dispose: dispose),
      );

  @override
  void bindLazy<T>(
    WeaveFactory<T> factory, {
    Object? name,
    WeaveDispose<T>? dispose,
  }) =>
      bindSingleton<T>(factory, name: name, dispose: dispose);

  @override
  void bindEagerSingleton<T>(
    WeaveFactory<T> factory, {
    Object? name,
    WeaveDispose<T>? dispose,
  }) =>
      _put<T>(
        (T, name),
        _Binding<T>.zero(factory, _Lifetime.eager, dispose: dispose),
      );

  @override
  void bindInstance<T>(T instance, {Object? name}) => _put<T>(
        (T, name),
        _Binding<T>.zero(() => instance, _Lifetime.singleton)..seed(instance),
      );

  @override
  void bindFactory<T, A>(WeaveFactory1<T, A> factory, {Object? name}) =>
      _put<T>((T, name), _Binding<T>.one((Object? a) => factory(a as A)));

  @override
  void bindFactory2<T, A, B>(WeaveFactory2<T, A, B> factory, {Object? name}) =>
      _put<T>(
        (T, name),
        _Binding<T>.two((Object? a, Object? b) => factory(a as A, b as B)),
      );

  @override
  void bindFactory3<T, A, B, C>(
    WeaveFactory3<T, A, B, C> factory, {
    Object? name,
  }) =>
      _put<T>(
        (T, name),
        _Binding<T>.three(
          (Object? a, Object? b, Object? c) => factory(a as A, b as B, c as C),
        ),
      );

  @override
  Future<void> bindSingletonAsync<T>(
    WeaveAsyncFactory<T> factory, {
    Object? name,
    WeaveDispose<T>? dispose,
  }) async {
    final T instance = await factory();
    _put<T>(
      (T, name),
      _Binding<T>.zero(() => instance, _Lifetime.singleton, dispose: dispose)
        ..seed(instance),
    );
  }

  // ── Resolução ─────────────────────────────────────────────────────────

  _Binding<Object?>? _lookupLocal(_Key key) =>
      _overrides[key] ?? _registrations[key];

  @override
  T get<T>({Object? name}) {
    if (T == dynamic || T == Object) {
      throw WeaveMissingTypeArgumentError(T);
    }
    final _Key key = (T, name);

    if (_resolutionStack.contains(key)) {
      final List<String> chain = <String>[
        for (final _Key k in _resolutionStack) describeWeaveKey(k.$1, k.$2),
        describeWeaveKey(T, name),
      ];
      // A pilha NÃO é limpa aqui: cada frame se remove no `finally`, e
      // limpar destruiria os frames de quem está acima.
      throw WeaveCircularDependencyError(chain);
    }

    final _Binding<Object?>? reg = _lookupLocal(key);
    if (reg == null) {
      if (_parent != null) return _parent!.get<T>(name: name);
      throw _notRegistered(T, name);
    }

    _resolutionStack.add(key);
    try {
      final T result = reg.resolveZero() as T;
      if (WeaveLog.isEnabled(override: _logger)) {
        _log('Resolved ${describeWeaveKey(T, name)}');
      }
      return result;
    } finally {
      _resolutionStack.remove(key);
    }
  }

  WeaveNotRegisteredError _notRegistered(Type type, Object? name) {
    final List<String> searched = <String>[];
    final List<String> available = <String>[];
    WeaveContainerAdapter? node = this;
    while (node != null) {
      searched.add(node.name);
      available.addAll(node._registrations.keys
          .map((_Key k) => describeWeaveKey(k.$1, k.$2)));
      node = node._parent;
    }
    return WeaveNotRegisteredError(
      type: type,
      name: name,
      containerName: this.name,
      searchedContainers: searched,
      available: available,
    );
  }

  @override
  T get1<T, A>(A arg, {Object? name}) {
    final _Binding<Object?>? reg = _lookupLocal((T, name));
    if (reg == null && _parent != null) {
      return _parent!.get1<T, A>(arg, name: name);
    }
    if (reg == null) throw _notRegistered(T, name);
    return reg.resolveOne(arg) as T;
  }

  @override
  T get2<T, A, B>(A a, B b, {Object? name}) {
    final _Binding<Object?>? reg = _lookupLocal((T, name));
    if (reg == null && _parent != null) {
      return _parent!.get2<T, A, B>(a, b, name: name);
    }
    if (reg == null) throw _notRegistered(T, name);
    return reg.resolveTwo(a, b) as T;
  }

  @override
  T get3<T, A, B, C>(A a, B b, C c, {Object? name}) {
    final _Binding<Object?>? reg = _lookupLocal((T, name));
    if (reg == null && _parent != null) {
      return _parent!.get3<T, A, B, C>(a, b, c, name: name);
    }
    if (reg == null) throw _notRegistered(T, name);
    return reg.resolveThree(a, b, c) as T;
  }

  @override
  T? tryGet<T>({Object? name}) {
    // Só a ausência de registro é engolida. Ciclo e exceção da factory do
    // usuário sobem — silenciá-los escondia bug e desarmava a detecção de
    // ciclo, porque a factory seguia rodando depois do erro.
    if (!canResolve<T>(name: name)) return null;
    return get<T>(name: name);
  }

  // ── Gerenciamento ─────────────────────────────────────────────────────

  @override
  void unbind<T>({Object? name}) {
    final _Key key = (T, name);
    _registrations.remove(key)?.dispose();
    _overrides.remove(key)?.dispose();
  }

  @override
  bool isRegistered<T>({Object? name}) {
    final _Key key = (T, name);
    return _overrides.containsKey(key) || _registrations.containsKey(key);
  }

  @override
  bool canResolve<T>({Object? name}) {
    WeaveContainerAdapter? node = this;
    while (node != null) {
      if (node.isRegistered<T>(name: name)) return true;
      node = node._parent;
    }
    return false;
  }

  @override
  void overrideFactory<T>(
    WeaveFactory<T> factory, {
    Object? name,
    bool singleton = true,
  }) {
    final _Key key = (T, name);
    _overrides.remove(key)?.dispose();
    _overrides[key] = _Binding<T>.zero(
      factory,
      singleton ? _Lifetime.singleton : _Lifetime.transient,
    );
  }

  @override
  void resetOverrides() {
    for (final _Binding<Object?> b in _overrides.values) {
      b.dispose();
    }
    _overrides.clear();
  }

  // ── Escopos ───────────────────────────────────────────────────────────

  @override
  WeaveContainer createScope({void Function()? onDispose}) =>
      createScopeNamed(null, onDispose: onDispose);

  /// Como [createScope], mas com nome legível para diagnóstico.
  ///
  /// Fora da interface [WeaveContainer] de propósito: acrescentar membro a
  /// uma interface pública quebra quem a implementa com `implements`.
  WeaveContainerAdapter createScopeNamed(
    String? scopeName, {
    void Function()? onDispose,
  }) {
    final WeaveContainerAdapter scope = WeaveContainerAdapter(
      name: scopeName == null
          ? '$name.scope${_scopes.length}'
          : '$name.$scopeName',
      logger: _logger,
    );
    scope._parent = this;
    scope._onDispose = onDispose;
    _scopes.add(scope);
    _log('Created scope: ${scope.name}');
    return scope;
  }

  @override
  void disposeScope(WeaveContainer scope) {
    if (scope is! WeaveContainerAdapter) return;
    // Escopo já descartado é no-op. Só escopo de OUTRO pai é erro.
    if (scope._parent == null) {
      _scopes.remove(scope);
      return;
    }
    assert(
      identical(scope._parent, this),
      'disposeScope: "${scope.name}" não é escopo de "$name".',
    );
    for (final WeaveContainerAdapter child
        in List<WeaveContainerAdapter>.of(scope._scopes)) {
      scope.disposeScope(child);
    }
    scope._onDispose?.call();
    scope._disposeAllBindings();
    scope._registrations.clear();
    scope._overrides.clear();
    scope._parent = null;
    _scopes.remove(scope);
    _log('Disposed scope: ${scope.name}');
  }

  void _disposeAllBindings() {
    for (final _Binding<Object?> b in _registrations.values) {
      b.dispose();
    }
    for (final _Binding<Object?> b in _overrides.values) {
      b.dispose();
    }
  }

  @override
  void reset() {
    for (final WeaveContainerAdapter scope
        in List<WeaveContainerAdapter>.of(_scopes)) {
      disposeScope(scope);
    }
    _disposeAllBindings();
    _registrations.clear();
    _overrides.clear();
    _scopes.clear();
    _log('Reset');
  }

  @override
  void resetSingletons() {
    for (final _Binding<Object?> b in _registrations.values) {
      b.dispose();
    }
    for (final _Binding<Object?> b in _overrides.values) {
      b.dispose();
    }
    _log('Reset singletons');
  }

  // ── Ciclo de vida e diagnóstico ───────────────────────────────────────

  @override
  WeaveValidationReport warmUp() {
    final List<WeaveValidationIssue> issues = <WeaveValidationIssue>[];
    int checked = 0;
    for (final MapEntry<_Key, _Binding<Object?>> e
        in _registrations.entries.toList()) {
      if (e.value.lifetime != _Lifetime.eager || e.value.isInitialized) {
        continue;
      }
      checked++;
      final WeaveValidationIssue? issue = _exercise(e.key, e.value);
      if (issue != null) issues.add(issue);
    }
    _log('warmUp: $checked eager binding(s), ${issues.length} problema(s)');
    return WeaveValidationReport(issues, checked: checked);
  }

  @override
  WeaveValidationReport validate({bool includeScopes = true}) {
    final List<WeaveValidationIssue> issues = <WeaveValidationIssue>[];
    int checked = 0;

    for (final MapEntry<_Key, _Binding<Object?>> e
        in _registrations.entries.toList()) {
      if (!e.value.takesNoArguments) continue;
      final bool wasInitialized = e.value.isInitialized;
      checked++;
      final WeaveValidationIssue? issue = _exercise(e.key, e.value);
      if (issue != null) issues.add(issue);
      // Não deixa rastro: o que não existia antes é descartado.
      if (!wasInitialized) e.value.dispose();
    }

    if (includeScopes) {
      for (final WeaveContainerAdapter scope in _scopes) {
        final WeaveValidationReport sub = scope.validate();
        issues.addAll(sub.issues);
        checked += sub.checked;
      }
    }
    return WeaveValidationReport(issues, checked: checked);
  }

  WeaveValidationIssue? _exercise(_Key key, _Binding<Object?> binding) {
    try {
      binding.resolveZero();
      return null;
    } on WeaveCircularDependencyError catch (e, s) {
      return WeaveValidationIssue(
        kind: WeaveIssueKind.cycle,
        type: key.$1,
        name: key.$2,
        containerName: name,
        error: e,
        stackTrace: s,
      );
    } on WeaveNotRegisteredError catch (e, s) {
      return WeaveValidationIssue(
        kind: WeaveIssueKind.missing,
        type: key.$1,
        name: key.$2,
        containerName: name,
        error: e,
        stackTrace: s,
      );
    } catch (e, s) {
      return WeaveValidationIssue(
        kind: WeaveIssueKind.threw,
        type: key.$1,
        name: key.$2,
        containerName: name,
        error: e,
        stackTrace: s,
      );
    }
  }

  @override
  String describe({bool includeParents = true}) {
    final StringBuffer b = StringBuffer()..writeln('container "$name"');
    if (_registrations.isEmpty) {
      b.writeln('  (nenhum registro)');
    }
    for (final MapEntry<_Key, _Binding<Object?>> e in _registrations.entries) {
      final String over = _overrides.containsKey(e.key) ? ' [sobrescrito]' : '';
      final String live = e.value.isInitialized ? ' [instanciado]' : '';
      b.writeln(
        '  ${describeWeaveKey(e.key.$1, e.key.$2)} · '
        '${e.value.lifetime.name}$over$live',
      );
    }
    for (final WeaveContainerAdapter scope in _scopes) {
      for (final String line
          in scope.describe(includeParents: false).split('\n')) {
        if (line.isNotEmpty) b.writeln('  $line');
      }
    }
    if (includeParents && _parent != null) {
      b.write(_parent!.describe());
    }
    return b.toString();
  }

  /// Cadeia de containers, do mais específico ao mais geral.
  List<String> get lineage {
    final List<String> out = <String>[];
    WeaveContainerAdapter? node = this;
    while (node != null) {
      out.add(node.name);
      node = node._parent;
    }
    return out;
  }

  /// Chaves registradas neste container.
  List<String> get registeredKeys => _registrations.keys
      .map((_Key k) => describeWeaveKey(k.$1, k.$2))
      .toList(growable: false);
}

/// Representação interna de um binding.
class _Binding<T> {
  _Binding.zero(
    Function factory,
    this.lifetime, {
    WeaveDispose<T>? dispose,
  })  // parâmetro nomeado não pode começar com `_`
      // ignore: prefer_initializing_formals
      : _factory0 = factory,
        _factory1 = null,
        _factory2 = null,
        _factory3 = null,
        // ignore: prefer_initializing_formals
        _dispose = dispose;

  _Binding.one(Function factory)
      : lifetime = _Lifetime.transient,
        _factory0 = null,
        _factory1 = factory,
        _factory2 = null,
        _factory3 = null,
        _dispose = null;

  _Binding.two(Function factory)
      : lifetime = _Lifetime.transient,
        _factory0 = null,
        _factory1 = null,
        _factory2 = factory,
        _factory3 = null,
        _dispose = null;

  _Binding.three(Function factory)
      : lifetime = _Lifetime.transient,
        _factory0 = null,
        _factory1 = null,
        _factory2 = null,
        _factory3 = factory,
        _dispose = null;

  final _Lifetime lifetime;
  final Function? _factory0;
  final Function? _factory1;
  final Function? _factory2;
  final Function? _factory3;
  final WeaveDispose<T>? _dispose;

  T? _instance;
  bool _initialized = false;

  bool get takesNoArguments => _factory0 != null;
  bool get isInitialized => _initialized;
  bool get _caches => lifetime != _Lifetime.transient;

  /// Injeta uma instância já pronta (bindInstance / bindSingletonAsync).
  void seed(T instance) {
    _instance = instance;
    _initialized = true;
  }

  dynamic resolveZero() {
    if (!_caches) return (_factory0! as WeaveFactory<T>)();
    if (!_initialized) {
      _instance = (_factory0! as WeaveFactory<T>)();
      _initialized = true;
    }
    return _instance;
  }

  // ignore: avoid_dynamic_calls
  dynamic resolveOne(dynamic a) => _factory1!(a);

  // ignore: avoid_dynamic_calls
  dynamic resolveTwo(dynamic a, dynamic b) => _factory2!(a, b);

  // ignore: avoid_dynamic_calls
  dynamic resolveThree(dynamic a, dynamic b, dynamic c) =>
      _factory3!(a, b, c);

  /// Descarta a instância cacheada, avisando o callback de dispose.
  void dispose() {
    if (_initialized && _instance is T) {
      _dispose?.call(_instance as T);
    }
    _instance = null;
    _initialized = false;
  }
}
