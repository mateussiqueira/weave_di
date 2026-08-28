import 'dart:async';

/// Factory sem parâmetros.
typedef WeaveFactory<T> = T Function();

/// Factory com 1 parâmetro.
typedef WeaveFactory1<T, A> = T Function(A arg);

/// Factory com 2 parâmetros.
typedef WeaveFactory2<T, A, B> = T Function(A a, B b);

/// Factory com 3 parâmetros.
typedef WeaveFactory3<T, A, B, C> = T Function(A a, B b, C c);

/// Factory assíncrona.
typedef WeaveAsyncFactory<T> = Future<T> Function();

/// Callback de descarte de uma instância cacheada.
typedef WeaveDispose<T> = void Function(T instance);

/// Interface do container de DI.
///
/// A implementação padrão é `WeaveContainerAdapter`.
///
/// ```dart
/// WeaveContainerAdapter.global.bindSingleton<AuthService>(AuthServiceImpl.new);
/// final auth = WeaveContainerAdapter.global.get<AuthService>();
///
/// // Duas implementações do mesmo tipo, distinguidas por nome:
/// c.bindSingleton<HttpClient>(() => PublicClient(), name: 'public');
/// c.bindSingleton<HttpClient>(() => AuthedClient(), name: 'authed');
/// final client = c.get<HttpClient>(name: 'authed');
/// ```
abstract class WeaveContainer {
  /// Nome do container para debugging.
  String get name;

  // ── Registros ─────────────────────────────────────────────────────────
  //
  // `name` distingue bindings do mesmo tipo. `null` (padrão) é um binding
  // como qualquer outro, com a chave `(T, null)` — não é curinga: pedir sem
  // nome não encontra um binding nomeado, e vice-versa.

  /// Registra como transient — nova instância a cada resolução.
  void bind<T>(WeaveFactory<T> factory, {Object? name});

  /// Registra como singleton preguiçoso: uma instância, criada no primeiro
  /// acesso.
  ///
  /// [dispose] roda quando a instância é descartada por [unbind],
  /// [resetSingletons], [reset] ou [disposeScope].
  void bindSingleton<T>(
    WeaveFactory<T> factory, {
    Object? name,
    WeaveDispose<T>? dispose,
  });

  /// Idêntico a [bindSingleton]. Mantido porque a 2.x expunha os dois.
  void bindLazy<T>(
    WeaveFactory<T> factory, {
    Object? name,
    WeaveDispose<T>? dispose,
  });

  /// Registra um singleton que deve ser materializado por [warmUp], e não no
  /// primeiro acesso.
  ///
  /// Não instancia no momento do bind: nesse instante as dependências dele
  /// podem ainda não estar registradas. [warmUp] é o ponto em que o grafo
  /// está completo.
  void bindEagerSingleton<T>(
    WeaveFactory<T> factory, {
    Object? name,
    WeaveDispose<T>? dispose,
  });

  /// Registra um valor já instanciado.
  void bindInstance<T>(T instance, {Object? name});

  /// Registra uma factory com 1 parâmetro (transient).
  void bindFactory<T, A>(WeaveFactory1<T, A> factory, {Object? name});

  /// Registra uma factory com 2 parâmetros (transient).
  void bindFactory2<T, A, B>(WeaveFactory2<T, A, B> factory, {Object? name});

  /// Registra uma factory com 3 parâmetros (transient).
  void bindFactory3<T, A, B, C>(
    WeaveFactory3<T, A, B, C> factory, {
    Object? name,
  });

  /// Registra um singleton assíncrono, aguardando a factory agora.
  Future<void> bindSingletonAsync<T>(
    WeaveAsyncFactory<T> factory, {
    Object? name,
    WeaveDispose<T>? dispose,
  });

  // ── Resolução ─────────────────────────────────────────────────────────

  /// Resolve uma dependência.
  ///
  /// Lança `WeaveNotRegisteredError` se não houver registro, e
  /// `WeaveCircularDependencyError` em ciclo.
  T get<T>({Object? name});

  /// Resolve com 1 argumento.
  T get1<T, A>(A arg, {Object? name});

  /// Resolve com 2 argumentos.
  T get2<T, A, B>(A a, B b, {Object? name});

  /// Resolve com 3 argumentos.
  T get3<T, A, B, C>(A a, B b, C c, {Object? name});

  /// Resolve, ou `null` se não houver registro.
  ///
  /// Só engole a ausência de registro. Ciclo e exceção lançada pela factory
  /// do usuário sobem — na 2.x eram silenciados, o que escondia bug.
  T? tryGet<T>({Object? name});

  // ── Gerenciamento ─────────────────────────────────────────────────────

  /// Remove um registro e o override dele, descartando a instância cacheada.
  void unbind<T>({Object? name});

  /// Se o tipo está registrado **neste** container (registro ou override).
  ///
  /// Não sobe para o pai — para isso, [canResolve]. São perguntas diferentes,
  /// e na 2.x elas estavam confundidas numa só.
  bool isRegistered<T>({Object? name});

  /// Se [get] conseguiria resolver, considerando os containers pais.
  bool canResolve<T>({Object? name});

  /// Sobrescreve uma dependência. Útil em teste.
  void overrideFactory<T>(
    WeaveFactory<T> factory, {
    Object? name,
    bool singleton = true,
  });

  /// Remove todas as sobrescritas.
  void resetOverrides();

  /// Limpa registros, escopos e instâncias.
  void reset();

  /// Descarta as instâncias cacheadas, preservando os registros.
  void resetSingletons();

  // ── Escopos ───────────────────────────────────────────────────────────

  /// Cria um escopo filho, que resolve subindo para este container.
  WeaveContainer createScope({void Function()? onDispose});

  /// Descarta um escopo e os descendentes dele.
  void disposeScope(WeaveContainer scope);

  // ── Ciclo de vida e diagnóstico ───────────────────────────────────────

  /// Materializa os bindings de [bindEagerSingleton].
  ///
  /// Idempotente. Falha de uma factory não interrompe as outras: todas são
  /// tentadas e os problemas voltam agregados no relatório.
  WeaveValidationReport warmUp({bool includeScopes = true});

  /// Tenta resolver todo binding sem argumentos e relata o que falhou.
  ///
  /// **Instancia objetos de verdade** — factory que abre socket ou lê disco
  /// vai fazê-lo. Feito para rodar em teste, não em produção. Instâncias que
  /// não existiam antes da chamada são descartadas ao final.
  WeaveValidationReport validate({bool includeScopes = true});

  /// Dump legível do grafo, para diagnóstico.
  String describe({bool includeParents = true});
}

/// Natureza de um problema encontrado por [WeaveContainer.validate].
enum WeaveIssueKind {
  /// Uma dependência exigida não está registrada em lugar nenhum.
  missing,

  /// A resolução entrou em ciclo.
  cycle,

  /// A factory do usuário lançou.
  threw,
}

/// Um problema encontrado por [WeaveContainer.validate] ou
/// [WeaveContainer.warmUp].
class WeaveValidationIssue {
  const WeaveValidationIssue({
    required this.kind,
    required this.type,
    required this.name,
    required this.containerName,
    required this.error,
    this.stackTrace,
  });

  /// Que tipo de problema.
  final WeaveIssueKind kind;

  /// O tipo que falhou ao resolver.
  final Type type;

  /// O nome do binding, se nomeado.
  final Object? name;

  /// Container que declarava o binding.
  final String containerName;

  /// O erro original.
  final Object error;

  /// Pilha do erro original, quando disponível.
  final StackTrace? stackTrace;

  @override
  String toString() =>
      '[${kind.name}] $type${name == null ? '' : '(name: $name)'} '
      'em "$containerName": $error';
}

/// Resultado de [WeaveContainer.validate] ou [WeaveContainer.warmUp].
class WeaveValidationReport {
  const WeaveValidationReport(this.issues, {this.checked = 0});

  /// Os problemas encontrados. Vazio significa grafo são.
  final List<WeaveValidationIssue> issues;

  /// Quantos bindings foram efetivamente exercitados.
  final int checked;

  /// Se nada falhou.
  bool get isValid => issues.isEmpty;

  /// Lança se houver problema. Use em teste:
  /// `container.validate().throwIfInvalid();`
  void throwIfInvalid() {
    if (isValid) return;
    throw StateError(describe());
  }

  /// Relatório legível.
  String describe() {
    if (isValid) return 'Weave: $checked binding(s) verificado(s), tudo ok.';
    final StringBuffer b = StringBuffer()
      ..writeln('Weave: ${issues.length} problema(s) em $checked binding(s):');
    for (final WeaveValidationIssue issue in issues) {
      b.writeln('  • $issue');
    }
    return b.toString();
  }

  @override
  String toString() => describe();
}
