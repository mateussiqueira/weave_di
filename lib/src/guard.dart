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
/// Decisão de um [WeaveRedirectingGuard].
///
/// Existe para que um guard **descreva** o que deve acontecer em vez de
/// mexer no `Navigator` por conta própria. Guard que navega sozinho não sabe
/// qual rota da pilha é a dele, e acerta a errada quando o usuário empurrou
/// outra tela durante o `await`.
sealed class WeaveGuardResult {
  const WeaveGuardResult();

  /// Libera a navegação.
  const factory WeaveGuardResult.allow() = WeaveGuardAllow;

  /// Bloqueia sem destino. A rota é removida da pilha, ou — se for a
  /// primeira — renderiza o `guardBlockedBuilder` do router.
  const factory WeaveGuardResult.block({String? reason}) = WeaveGuardBlock;

  /// Bloqueia e manda para [path].
  const factory WeaveGuardResult.redirect(
    String path, {
    Object? arguments,
  }) = WeaveGuardRedirect;
}

/// Ver [WeaveGuardResult.allow].
final class WeaveGuardAllow extends WeaveGuardResult {
  const WeaveGuardAllow();
}

/// Ver [WeaveGuardResult.block].
final class WeaveGuardBlock extends WeaveGuardResult {
  const WeaveGuardBlock({this.reason});

  /// Motivo, só para diagnóstico.
  final String? reason;
}

/// Ver [WeaveGuardResult.redirect].
final class WeaveGuardRedirect extends WeaveGuardResult {
  const WeaveGuardRedirect(this.path, {this.arguments});

  /// Destino.
  final String path;

  /// Argumentos repassados ao destino.
  final Object? arguments;
}

/// Guard que devolve uma decisão em vez de navegar sozinho.
///
/// Interface **opcional**: [WeaveGuard] continua igual à 2.0.0, então nenhum
/// guard existente quebra. Quem implementa esta aqui ganha redirect seguro.
///
/// ```dart
/// class AuthGuard implements WeaveRedirectingGuard {
///   @override
///   Future<WeaveGuardResult> resolve(context, route, params, matched) async {
///     return isLogged ? const WeaveGuardResult.allow()
///                     : const WeaveGuardResult.redirect('/login');
///   }
///
///   @override
///   Future<bool> canActivate(context, route, params, matched) async =>
///       resolve(context, route, params, matched)
///           .then((r) => r is WeaveGuardAllow);
/// }
/// ```
abstract class WeaveRedirectingGuard implements WeaveGuard {
  /// Decide o destino da navegação.
  Future<WeaveGuardResult> resolve(
    BuildContext context,
    String route,
    WeaveParams params,
    List<WeaveRoute> matchedRoutes,
  );
}

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

class _AuthWeaveGuard implements WeaveRedirectingGuard {
  final bool Function(BuildContext context) _isAuthenticated;
  final String loginPath;

  const _AuthWeaveGuard({
    required this._isAuthenticated,
    this.loginPath = '/login',
  });

  // Até a 2.0.0 este guard chamava `Navigator.pushReplacementNamed` daqui
  // de dentro. `pushReplacement` mira o topo da pilha, que não é
  // necessariamente a rota guardada — se o usuário empurrou outra tela
  // durante o `await`, a rota destruída era a errada. Agora ele só descreve
  // a decisão, e quem mexe na pilha é o gate, por identidade de rota.
  @override
  Future<WeaveGuardResult> resolve(
    BuildContext context,
    String route,
    WeaveParams params,
    List<WeaveRoute> matchedRoutes,
  ) async {
    if (_isAuthenticated(context)) return const WeaveGuardResult.allow();
    return WeaveGuardResult.redirect(loginPath);
  }

  @override
  Future<bool> canActivate(
    BuildContext context,
    String route,
    WeaveParams params,
    List<WeaveRoute> matchedRoutes,
  ) async =>
      _isAuthenticated(context);
}

/// Alias para compatibilidade com API anterior.
typedef WeaveRouteGuard = WeaveGuard;
