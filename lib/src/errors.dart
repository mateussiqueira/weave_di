/// Erros do Weave.
///
/// Ambos estendem [StateError], que era o que a 2.x lançava — quem já captura
/// `StateError` continua capturando. O ganho é poder distinguir "não está
/// registrado" de "ciclo" sem inspecionar o texto da mensagem.
library;

/// Formata a chave de um registro para leitura humana.
String describeWeaveKey(Type type, Object? name) =>
    name == null ? '$type' : '$type(name: $name)';

/// Nada está registrado para o tipo (e nome) pedido.
class WeaveNotRegisteredError extends StateError {
  WeaveNotRegisteredError({
    required this.type,
    required this.name,
    required this.containerName,
    required this.searchedContainers,
    required this.available,
  }) : super(_message(type, name, searchedContainers, available));

  /// O tipo que não foi encontrado.
  final Type type;

  /// O nome do binding, se era um binding nomeado.
  final Object? name;

  /// Container onde a resolução começou.
  final String containerName;

  /// Cadeia de containers percorrida, do mais específico ao mais geral.
  final List<String> searchedContainers;

  /// O que estava registrado, para ajudar a achar o erro de digitação.
  final List<String> available;

  static String _message(
    Type type,
    Object? name,
    List<String> searched,
    List<String> available,
  ) {
    final StringBuffer b = StringBuffer()
      ..writeln('Nothing is bound to ${describeWeaveKey(type, name)}.')
      ..writeln('Searched containers: ${searched.map((String c) => '"$c"').join(' -> ')}.');

    if (available.isEmpty) {
      b.writeln('No bindings are registered in any of them.');
    } else {
      final List<String> shown = available.take(8).toList();
      final int rest = available.length - shown.length;
      b.write('Bound: ${shown.join(', ')}');
      b.writeln(rest > 0 ? ' (+$rest more).' : '.');
    }
    b.write('Did you forget to install the module that binds it, '
        'or call it before install()?');
    return b.toString();
  }
}

/// A resolução entrou em ciclo.
class WeaveCircularDependencyError extends StateError {
  WeaveCircularDependencyError(this.chain) : super(_message(chain));

  /// A cadeia percorrida até fechar o ciclo.
  final List<String> chain;

  static String _message(List<String> chain) =>
      'Circular dependency detected: ${chain.join(' -> ')}';
}

/// `get<T>()` foi chamado sem argumento de tipo utilizável.
class WeaveMissingTypeArgumentError extends ArgumentError {
  WeaveMissingTypeArgumentError(this.resolvedTo)
      : super(
          'get<T>() was called without a usable type argument, so T resolved '
          'to $resolvedTo. Write get<MyService>(), or annotate the target: '
          'final MyService s = c.get();',
        );

  /// O que `T` acabou virando — `dynamic` ou `Object`.
  final Type resolvedTo;
}
