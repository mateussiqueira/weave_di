import 'package:flutter/material.dart';

import 'route.dart';

/// Guard de autorização de rotas.
///
/// Guards rodam antes de construir a página. Se bloquear,
/// a navegação não acontece.
///
/// ```dart
/// final guard = WeaveGuard.custom(
///   canActivate: (context, route, params, matchedRoutes) async {
///     final auth = context.get<AuthService>();
///     return auth.isAuthenticated;
///   },
/// );
/// ```
abstract class WeaveGuard {
  /// Verifica se a rota pode ser ativada.
  Future<bool> canActivate(
    BuildContext context,
    String route,
    WeaveParams params,
    List<WeaveRoute> matchedRoutes,
  );

  /// Cria um guard customizado.
  factory WeaveGuard.custom({
    required Future<bool> Function(
      BuildContext context,
      String route,
      WeaveParams params,
      List<WeaveRoute> matchedRoutes,
    )
    canActivate,
  }) = _CustomWeaveGuard;

  /// Cria um guard que sempre permite.
  factory WeaveGuard.allow() = _AllowWeaveGuard;

  /// Cria um guard que sempre bloqueia.
  factory WeaveGuard.deny() = _DenyWeaveGuard;

  /// Cria um guard de autenticação.
  factory WeaveGuard.auth({
    required bool Function(BuildContext context) isAuthenticated,
    String loginPath,
  }) = _AuthWeaveGuard;
}

class _CustomWeaveGuard implements WeaveGuard {
  final Future<bool> Function(
    BuildContext context,
    String route,
    WeaveParams params,
    List<WeaveRoute> matchedRoutes,
  )
  _canActivate;

  const _CustomWeaveGuard({required this._canActivate});

  @override
  Future<bool> canActivate(
    BuildContext context,
    String route,
    WeaveParams params,
    List<WeaveRoute> matchedRoutes,
  ) {
    return _canActivate(context, route, params, matchedRoutes);
  }
}

class _AllowWeaveGuard implements WeaveGuard {
  const _AllowWeaveGuard();

  @override
  Future<bool> canActivate(
    BuildContext context,
    String route,
    WeaveParams params,
    List<WeaveRoute> matchedRoutes,
  ) async =>
      true;
}

class _DenyWeaveGuard implements WeaveGuard {
  const _DenyWeaveGuard();

  @override
  Future<bool> canActivate(
    BuildContext context,
    String route,
    WeaveParams params,
    List<WeaveRoute> matchedRoutes,
  ) async =>
      false;
}

class _AuthWeaveGuard implements WeaveGuard {
  final bool Function(BuildContext context) _isAuthenticated;
  final String loginPath;

  const _AuthWeaveGuard({
    required this._isAuthenticated,
    this.loginPath = '/login',
  });

  @override
  Future<bool> canActivate(
    BuildContext context,
    String route,
    WeaveParams params,
    List<WeaveRoute> matchedRoutes,
  ) async {
    if (_isAuthenticated(context)) return true;

    // ignore: use_build_context_synchronously
    Navigator.of(context).pushReplacementNamed(loginPath);
    return false;
  }
}

/// Alias para compatibilidade com API anterior.
typedef WeaveRouteGuard = WeaveGuard;
