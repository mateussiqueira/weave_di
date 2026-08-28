import 'container.dart';

/// Declara que um módulo oferece um tipo ao resto da aplicação.
///
/// O container de um [WeaveModule] é um **escopo**, e escopo resolve para
/// cima, nunca de lado: sem export, o `HttpClient` registrado pelo módulo de
/// autenticação é invisível para o módulo de pagamentos. `imports` não
/// resolve isso — ele controla a ordem de instalação, não a visibilidade.
///
/// ```dart
/// WeaveModule(
///   name: 'auth',
///   binds: <WeaveBind>[
///     (c) => c.bindSingleton<HttpClient>(() => DioAdapter()),
///   ],
///   exports: <WeaveExport<Object?>>[WeaveExport<HttpClient>()],
/// )
/// ```
///
/// O encaminhamento é transient de propósito: ele só delega a
/// `origem.get<T>()`, então o lifetime real continua sendo o declarado no
/// módulo. Encaminhar como singleton cacheria no pai um tipo que o módulo
/// declarou como transient.
class WeaveExport<T> {
  const WeaveExport({this.name});

  /// Nome do binding, quando o módulo registrou um binding nomeado.
  final Object? name;

  /// Publica [T] em [target], delegando a [source].
  void forwardTo(WeaveContainer target, WeaveContainer source) {
    target.bind<T>(() => source.get<T>(name: name), name: name);
  }

  /// Remove o encaminhamento. Chamado quando o módulo é descartado, para não
  /// deixar no pai um binding que aponta para um escopo morto.
  void revokeFrom(WeaveContainer target) {
    target.unbind<T>(name: name);
  }

  @override
  String toString() =>
      'WeaveExport<$T>${name == null ? '' : '(name: $name)'}';
}
