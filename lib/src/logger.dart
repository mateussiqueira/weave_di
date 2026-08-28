import 'package:flutter/foundation.dart';

/// Assinatura de um logger do Weave.
typedef WeaveLogger = void Function(String message);

/// Interruptor único de diagnóstico do Weave.
///
/// **O Weave é silencioso por padrão.** Até a 2.0.0 o container fazia um
/// `print` a cada resolução — inclusive em release. Agora nada é escrito
/// enquanto ninguém atribuir [logger].
///
/// ```dart
/// // Liga o diagnóstico só em debug:
/// WeaveLog.logger = kDebugMode ? WeaveLog.debugPrintLogger : null;
/// ```
///
/// Um [WeaveContainer] ou [WeaveRouter] pode receber o próprio logger no
/// construtor; quando não recebe, cai neste aqui.
abstract final class WeaveLog {
  /// Logger global. `null` (padrão) significa silêncio total.
  static WeaveLogger? logger;

  /// Logger pronto que escreve via `debugPrint`.
  ///
  /// `debugPrint` é preferível a `print`: respeita o throttle do Flutter e
  /// não é chamado em release a menos que você peça.
  static WeaveLogger get debugPrintLogger => _debugPrint;

  static void _debugPrint(String message) => debugPrint(message);

  /// Escreve uma mensagem com escopo, se houver logger.
  ///
  /// [override] tem precedência sobre o [logger] global.
  static void write(
    String scope,
    String message, {
    WeaveLogger? override,
  }) {
    final WeaveLogger? sink = override ?? logger;
    if (sink == null) return;
    sink('[$scope] $message');
  }

  /// Se alguém está escutando. Use para pular a montagem de mensagens caras.
  static bool isEnabled({WeaveLogger? override}) =>
      (override ?? logger) != null;

  /// Restaura o silêncio. Útil em `tearDown` de teste.
  static void reset() => logger = null;
}
