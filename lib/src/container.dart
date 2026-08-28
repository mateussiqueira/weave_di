import 'dart:async';

/// Factory sem parâmetros.
typedef WeaveFactory<T> = T Function();

/// Factory com 1 parâmetro.
typedef WeaveFactory1<T, A> = T Function(A arg);

/// Factory com 2 parâmetros.
typedef WeaveFactory2<T, A, B> = T Function(A a, B b);

/// Factory com 3 parâmetros.
typedef WeaveFactory3<T, A, B, C> = T Function(A a, B b, C c);

/// Factory assíncrona (pra singletons que precisam de init).
typedef WeaveAsyncFactory<T> = Future<T> Function();

/// Interface do container de DI.
///
/// Define o contrato pra resolução de dependências. A implementação
/// padrão é [WeaveContainerAdapter].
///
/// ```dart
/// // Registra
/// WeaveContainerAdapter.global.bindSingleton<AuthService>(() => AuthServiceImpl());
///
/// // Resolve
/// final auth = WeaveContainerAdapter.global.get<AuthService>();
///
/// // Container isolado
/// final c = WeaveContainerAdapter.create(name: 'auth');
/// ```
abstract class WeaveContainer {
  /// Nome do container para debugging.
  String get name;

  // -- Registros --

  /// Registra uma dependência como transient (nova instância a cada resolve).
  void bind<T>(WeaveFactory<T> factory);

  /// Registra como singleton (instância única).
  void bindSingleton<T>(WeaveFactory<T> factory);

  /// Registra como lazy singleton (criada no primeiro acesso).
  void bindLazy<T>(WeaveFactory<T> factory);

  /// Registra um valor já instanciado como singleton imutável.
  void bindInstance<T>(T instance);

  /// Registra uma factory com 1 parâmetro (transient).
  void bindFactory<T, A>(WeaveFactory1<T, A> factory);

  /// Registra uma factory com 2 parâmetros (transient).
  void bindFactory2<T, A, B>(WeaveFactory2<T, A, B> factory);

  /// Registra uma factory com 3 parâmetros (transient).
  void bindFactory3<T, A, B, C>(WeaveFactory3<T, A, B, C> factory);

  /// Registra um singleton assíncrono.
  Future<void> bindSingletonAsync<T>(WeaveAsyncFactory<T> factory);

  // -- Resolução --

  /// Resolve uma dependência.
  T get<T>();

  /// Resolve uma dependência com 1 arg.
  T get1<T, A>(A arg);

  /// Resolve uma dependência com 2 args.
  T get2<T, A, B>(A a, B b);

  /// Resolve uma dependência com 3 args.
  T get3<T, A, B, C>(A a, B b, C c);

  /// Resolve uma dependência ou retorna `null`.
  T? tryGet<T>();

  // -- Gerenciamento --

  /// Remove um registro.
  void unbind<T>();

  /// Verifica se um tipo está registrado.
  bool isRegistered<T>();

  /// Sobrescreve uma dependência (útil para testes).
  void overrideFactory<T>(WeaveFactory<T> factory, {bool singleton = true});

  /// Remove todas as sobrescritas.
  void resetOverrides();

  /// Limpa todos os registros e escopos.
  void reset();

  /// Reseta todas as instâncias singletons.
  void resetSingletons();

  // -- Escopos --

  /// Cria um escopo filho.
  WeaveContainer createScope({void Function()? onDispose});

  /// Descarta um escopo.
  void disposeScope(WeaveContainer scope);

  // -- Lifecycle --

  /// Inicialização assíncrona de múltiplas dependências.
  Future<void> initializeAsync(
    List<Future<void> Function(WeaveContainer container)> initializers,
  );
}
