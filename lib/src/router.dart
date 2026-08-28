import 'package:flutter/material.dart';

import 'container_adapter.dart';
import 'middleware.dart';
import 'route.dart';

/// Gerenciador de rotas.
///
/// Centraliza todas as rotas, middlewares, e a lógica de matching.
class WeaveRouter {
  final List<WeaveRoute> routes;
  final List<WeaveMiddleware> middlewares;
  final void Function(String message)? logger;

  WeaveRouter({
    required this.routes,
    this.middlewares = const [],
    this.logger,
  });

  void _log(String message) {
    if (logger != null) {
      logger!('[WeaveRouter] $message');
    }
  }

  /// Busca uma rota que corresponda ao path.
  WeaveRouteMatch? match(String path) {
    for (final route in routes) {
      if (route.matches(path)) {
        _log('Matched: ${route.path} for path: $path');
        return WeaveRouteMatch(
          route: route,
          params: route.extractParams(path),
        );
      }
    }
    _log('No match for path: $path');
    return null;
  }

  /// Verifica guards e middlewares de uma rota.
  Future<bool> canActivateRoute(
    BuildContext context,
    String fullPath,
    WeaveRouteMatch routeMatch,
  ) async {
    final weaveParams = WeaveParams(routeMatch.params);

    // Middlewares globais
    for (final middleware in middlewares) {
      final allowed = await middleware.onNavigate(
        context,
        fullPath,
        weaveParams,
      );
      if (!allowed) {
        _log('Blocked by global middleware: ${middleware.runtimeType}');
        return false;
      }
    }

    // Middlewares da rota
    for (final middleware in routeMatch.route.middlewares) {
      final allowed = await middleware.onNavigate(
        context,
        fullPath,
        weaveParams,
      );
      if (!allowed) {
        _log('Blocked by route middleware: ${middleware.runtimeType}');
        return false;
      }
    }

    // Guards
    for (final guard in routeMatch.route.guards) {
      final canActivate = await guard.canActivate(
        context,
        fullPath,
        weaveParams,
        [routeMatch.route],
      );
      if (!canActivate) {
        _log('Blocked by guard: ${guard.runtimeType}');
        return false;
      }
    }

    // Notifica middlewares
    for (final middleware in middlewares) {
      middleware.onRouteMatched(context, routeMatch);
    }
    for (final middleware in routeMatch.route.middlewares) {
      middleware.onRouteMatched(context, routeMatch);
    }

    return true;
  }

  /// Constrói a página para uma rota.
  Widget buildPage(
    BuildContext context,
    WeaveRoute route,
    WeaveParams params,
  ) {
    if (route.injectFactory != null) {
      return route.injectFactory!(context, params, WeaveContainerAdapter.global);
    }
    return route.builder(context, params);
  }

  /// Cria um [RouteFactory] para MaterialApp.onGenerateRoute.
  RouteFactory get routeFactory => _createRouteFactory;

  Route<dynamic>? _createRouteFactory(RouteSettings settings) {
    final fullPath = settings.name ?? '/';
    final routeMatch = match(fullPath);

    if (routeMatch == null) {
      return MaterialPageRoute(
        settings: settings,
        builder: (context) => _defaultPage(context, fullPath),
      );
    }

    final route = routeMatch.route;
    final weaveParams = WeaveParams(routeMatch.params);

    // Verifica redirect
    if (route.redirect != null) {
      final redirectPath = _resolveRedirect(
        route.redirect!,
        weaveParams,
      );
      if (redirectPath != null) {
        final redirectMatch = match(redirectPath);
        if (redirectMatch != null) {
          return _createRouteFactory(
            RouteSettings(name: redirectPath, arguments: settings.arguments),
          );
        }
      }
    }

    Widget buildPage(BuildContext context) {
      if (route.injectFactory != null) {
        return route.injectFactory!(
          context,
          weaveParams,
          WeaveContainerAdapter.global,
        );
      }
      return route.builder(context, weaveParams);
    }

    if (route.transition.type != WeaveTransitionType.material) {
      return route.transition.buildRoute(
        Builder(builder: (context) => buildPage(context)),
      );
    }

    return MaterialPageRoute(settings: settings, builder: buildPage);
  }

  /// Resolve redirect de forma segura (sem BuildContext).
  String? _resolveRedirect(
    String? Function(BuildContext, WeaveParams) redirect,
    WeaveParams params,
  ) {
    // ignore: invalid_use_of_protected_member
    final rootContext = WidgetsBinding.instance.rootElement;
    if (rootContext == null) return null;
    // ignore: invalid_use_of_protected_member
    return redirect(rootContext as BuildContext, params);
  }

  /// Página padrão quando rota não é encontrada.
  static Widget _defaultPage(BuildContext context, String path) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Página não encontrada',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Rota não encontrada: $path',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
