import 'package:flutter/material.dart';

import 'route.dart';

/// Middleware de rota.
///
/// Roda antes dos guards. Bom pra logging, analytics,
/// tracking, ou qualquer coisa que precise interceptar
/// a navegação.
abstract class WeaveMiddleware {
  /// Chamado antes da validação dos guards.
  Future<bool> onNavigate(
    BuildContext context,
    String path,
    WeaveParams params,
  );

  /// Chamado quando uma rota é encontrada.
  void onRouteMatched(BuildContext context, WeaveRouteMatch match);

  /// Cria um middleware que sempre permite.
  factory WeaveMiddleware.allow() = _AllowMiddleware;

  /// Cria um middleware de log.
  factory WeaveMiddleware.log({
    void Function(String message)? logger,
  }) = _LogMiddleware;

  /// Cria um middleware que executa uma ação ao navegar.
  factory WeaveMiddleware.onNavigateAction({
    required Future<bool> Function(BuildContext, String, WeaveParams) action,
  }) = _OnNavigateMiddleware;

  /// Cria um middleware que executa uma ação ao encontrar rota.
  factory WeaveMiddleware.onRouteMatchedAction({
    required void Function(BuildContext, WeaveRouteMatch) action,
  }) = _OnRouteMatchedMiddleware;
}

class _AllowMiddleware implements WeaveMiddleware {
  const _AllowMiddleware();

  @override
  Future<bool> onNavigate(
    BuildContext context,
    String path,
    WeaveParams params,
  ) async =>
      true;

  @override
  void onRouteMatched(BuildContext context, WeaveRouteMatch match) {}
}

class _LogMiddleware implements WeaveMiddleware {
  final void Function(String message) _log;

  _LogMiddleware({void Function(String message)? logger})
      : _log = logger ?? _defaultLog;

  // Continua barulhento por padrão de propósito: quem constrói um
  // `WeaveMiddleware.log()` está pedindo log explicitamente. O silêncio
  // padrão do `WeaveLog` vale para o diagnóstico interno, não para isto —
  // silenciar aqui transformaria a feature num no-op.
  static void _defaultLog(String message) => debugPrint('[Weave] $message');

  @override
  Future<bool> onNavigate(
    BuildContext context,
    String path,
    WeaveParams params,
  ) async {
    _log('Navigating to: $path (params: $params)');
    return true;
  }

  @override
  void onRouteMatched(BuildContext context, WeaveRouteMatch match) {
    _log('Route matched: ${match.route.path} (name: ${match.route.name})');
  }
}

class _OnNavigateMiddleware implements WeaveMiddleware {
  final Future<bool> Function(BuildContext, String, WeaveParams) _action;

  const _OnNavigateMiddleware({required this._action});

  @override
  Future<bool> onNavigate(
    BuildContext context,
    String path,
    WeaveParams params,
  ) {
    return _action(context, path, params);
  }

  @override
  void onRouteMatched(BuildContext context, WeaveRouteMatch match) {}
}

class _OnRouteMatchedMiddleware implements WeaveMiddleware {
  final void Function(BuildContext, WeaveRouteMatch) _action;

  const _OnRouteMatchedMiddleware({required this._action});

  @override
  Future<bool> onNavigate(
    BuildContext context,
    String path,
    WeaveParams params,
  ) async =>
      true;

  @override
  void onRouteMatched(BuildContext context, WeaveRouteMatch match) {
    _action(context, match);
  }
}
