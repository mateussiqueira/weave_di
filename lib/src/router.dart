import 'package:flutter/material.dart';

import 'container.dart';
import 'container_adapter.dart';
import 'gate.dart';
import 'guard.dart';
import 'logger.dart';
import 'middleware.dart';
import 'route.dart';

/// Gerenciador de rotas.
///
/// Centraliza rotas, middlewares e a lógica de matching.
class WeaveRouter {
  WeaveRouter({
    required this.routes,
    this.middlewares = const <WeaveMiddleware>[],
    this.logger,
    this.container,
    this.guardOnGenerateRoute = true,
    this.guardPendingBuilder,
    this.guardBlockedBuilder,
    this.onUnknownRoute,
    this.maxRedirects = 5,
  }) : assert(maxRedirects > 0, 'maxRedirects deve ser positivo');

  /// Compõe um router a partir de uma lista base mais sobrescritas.
  ///
  /// Rota de [overrides] cujo `path` já existe em [base] **substitui a base
  /// no lugar dela**, preservando a ordem de declaração — o que importa
  /// porque `match` devolve a primeira que casar, e ordem é precedência
  /// (`/user/new` declarada antes de `/user/:id` continua vencendo). Path
  /// inédito é anexado ao fim.
  ///
  /// ```dart
  /// final router = WeaveRouter.merge(
  ///   base: appRoutes,
  ///   overrides: brand.routeOverrides,
  /// );
  /// ```
  factory WeaveRouter.merge({
    required List<WeaveRoute> base,
    List<WeaveRoute> overrides = const <WeaveRoute>[],
    List<WeaveMiddleware> middlewares = const <WeaveMiddleware>[],
    WeaveLogger? logger,
    WeaveContainer? container,
    bool guardOnGenerateRoute = true,
    WidgetBuilder? guardPendingBuilder,
    WidgetBuilder? guardBlockedBuilder,
    Route<dynamic>? Function(RouteSettings settings)? onUnknownRoute,
    int maxRedirects = 5,
  }) {
    return WeaveRouter(
      routes: mergeRoutes(base, overrides),
      middlewares: middlewares,
      logger: logger,
      container: container,
      guardOnGenerateRoute: guardOnGenerateRoute,
      guardPendingBuilder: guardPendingBuilder,
      guardBlockedBuilder: guardBlockedBuilder,
      onUnknownRoute: onUnknownRoute,
      maxRedirects: maxRedirects,
    );
  }

  /// Ver [WeaveRouter.merge]. Substitui in-place por `path`, anexa o resto.
  static List<WeaveRoute> mergeRoutes(
    List<WeaveRoute> base,
    List<WeaveRoute> overrides,
  ) {
    if (overrides.isEmpty) return List<WeaveRoute>.of(base);

    final List<WeaveRoute> result = List<WeaveRoute>.of(base);
    for (final WeaveRoute override in overrides) {
      final int index = result.indexWhere((WeaveRoute r) => r.path == override.path);
      if (index >= 0) {
        result[index] = override;
      } else {
        result.add(override);
      }
    }
    return result;
  }

  final List<WeaveRoute> routes;
  final List<WeaveMiddleware> middlewares;

  /// Logger deste router. Quando nulo, cai em [WeaveLog.logger].
  final WeaveLogger? logger;

  /// Container usado por `injectFactory`. Quando nulo, usa o global.
  ///
  /// É o que permite um módulo com container próprio ser realmente
  /// alcançável pelas rotas dele.
  final WeaveContainer? container;

  /// Se `onGenerateRoute` deve rodar guards e middlewares.
  ///
  /// Até a 2.0.0 não rodava: `canActivateRoute` só era chamado pelas
  /// extensões de navegação, então deep link e `Navigator.pushNamed`
  /// entravam direto em rota protegida.
  final bool guardOnGenerateRoute;

  /// O que mostrar enquanto os guards decidem. Estado transitório.
  final WidgetBuilder? guardPendingBuilder;

  /// O que mostrar quando o acesso é negado e não há para onde voltar.
  /// Estado **terminal** — distinto de [guardPendingBuilder] de propósito.
  final WidgetBuilder? guardBlockedBuilder;

  /// Rota desconhecida. Devolver `null` delega ao Flutter.
  final Route<dynamic>? Function(RouteSettings settings)? onUnknownRoute;

  /// Teto de saltos numa cadeia de redirects.
  final int maxRedirects;

  /// Container efetivo para resolução.
  WeaveContainer get effectiveContainer =>
      container ?? WeaveContainerAdapter.global;

  /// Escreve uma linha de diagnóstico. Silencioso por padrão.
  void log(String message) =>
      WeaveLog.write('WeaveRouter', message, override: logger);

  void _log(String message) => log(message);

  /// Busca uma rota que corresponda ao path.
  ///
  /// Rota com [WeaveRoute.when] falso é ignorada, como se não existisse.
  WeaveRouteMatch? match(String path) {
    for (final WeaveRoute route in routes) {
      if (!route.isEnabled) continue;
      if (route.matches(path)) {
        _log('Matched: ${route.path} for path: $path');
        return WeaveRouteMatch(
          route: route,
          params: route.allParamsMap(path),
        );
      }
    }
    _log('No match for path: $path');
    return null;
  }

  /// Busca uma rota pelo nome, respeitando [WeaveRoute.when].
  WeaveRoute? routeByName(String name) {
    for (final WeaveRoute route in routes) {
      if (route.name == name && route.isEnabled) return route;
    }
    return null;
  }

  /// Verifica guards e middlewares de uma rota.
  Future<bool> canActivateRoute(
    BuildContext context,
    String fullPath,
    WeaveRouteMatch routeMatch,
  ) async {
    final WeaveGuardResult result =
        await resolveGuards(context, fullPath, routeMatch);
    return result is WeaveGuardAllow;
  }

  /// Como [canActivateRoute], mas preservando o destino de um redirect.
  Future<WeaveGuardResult> resolveGuards(
    BuildContext context,
    String fullPath,
    WeaveRouteMatch routeMatch,
  ) async {
    final WeaveParams weaveParams = WeaveParams.of(routeMatch.params);

    for (final WeaveMiddleware middleware in <WeaveMiddleware>[
      ...middlewares,
      ...routeMatch.route.middlewares,
    ]) {
      if (!context.mounted) return const WeaveGuardResult.block();
      final bool allowed =
          await middleware.onNavigate(context, fullPath, weaveParams);
      if (!allowed) {
        _log('Blocked by middleware: ${middleware.runtimeType}');
        return WeaveGuardResult.block(
          reason: 'middleware ${middleware.runtimeType}',
        );
      }
    }

    for (final WeaveGuard guard in routeMatch.route.guards) {
      if (!context.mounted) return const WeaveGuardResult.block();

      if (guard is WeaveRedirectingGuard) {
        final WeaveGuardResult result = await guard.resolve(
          context,
          fullPath,
          weaveParams,
          <WeaveRoute>[routeMatch.route],
        );
        if (result is WeaveGuardAllow) continue;
        _log('Blocked by guard: ${guard.runtimeType}');
        return result;
      }

      final bool canActivate = await guard.canActivate(
        context,
        fullPath,
        weaveParams,
        <WeaveRoute>[routeMatch.route],
      );
      if (!canActivate) {
        _log('Blocked by guard: ${guard.runtimeType}');
        return WeaveGuardResult.block(reason: '${guard.runtimeType}');
      }
    }

    if (!context.mounted) return const WeaveGuardResult.block();
    for (final WeaveMiddleware middleware in <WeaveMiddleware>[
      ...middlewares,
      ...routeMatch.route.middlewares,
    ]) {
      middleware.onRouteMatched(context, routeMatch);
    }

    return const WeaveGuardResult.allow();
  }

  /// Constrói a página de uma rota, aplicando `injectFactory` se houver.
  Widget buildPage(
    BuildContext context,
    WeaveRoute route,
    WeaveParams params,
  ) {
    if (route.injectFactory != null) {
      return route.injectFactory!(context, params, effectiveContainer);
    }
    return route.builder(context, params);
  }

  /// Placeholder enquanto os guards decidem.
  Widget buildPending(BuildContext context) =>
      guardPendingBuilder?.call(context) ??
      const Scaffold(body: SizedBox.shrink());

  /// Tela terminal de acesso negado.
  Widget buildBlocked(BuildContext context) =>
      guardBlockedBuilder?.call(context) ?? buildPending(context);

  /// Se uma rota precisa passar pelo gate de guards.
  ///
  /// Middleware **global** conta: com um analytics registrado no router,
  /// toda rota é embrulhada. Custo zero só existe quando não há middleware
  /// global nem guard/middleware próprio.
  bool needsGate(WeaveRoute route) =>
      guardOnGenerateRoute &&
      !route.skipGuards &&
      (route.guards.isNotEmpty ||
          route.middlewares.isNotEmpty ||
          middlewares.isNotEmpty);

  /// Cria um [RouteFactory] para `MaterialApp.onGenerateRoute`.
  RouteFactory get routeFactory => _createRouteFactory;

  /// Para `MaterialApp.onGenerateInitialRoutes`.
  ///
  /// Sem isto, `defaultGenerateInitialRoutes` quebra `/user/42` em `/`,
  /// `/user` e `/user/42` e empilha os três — e como o factory nunca devolve
  /// `null`, os dois primeiros viram páginas de 404 embaixo do destino.
  List<Route<dynamic>> onGenerateInitialRoutes(String initialRoute) {
    final Route<dynamic>? route =
        _createRouteFactory(RouteSettings(name: initialRoute));
    return <Route<dynamic>>[?route];
  }

  Route<dynamic>? _createRouteFactory(RouteSettings settings) {
    final String fullPath = settings.name ?? '/';
    final WeaveRouteMatch? routeMatch = match(fullPath);

    if (routeMatch == null) {
      final Route<dynamic>? custom = onUnknownRoute?.call(settings);
      if (custom != null) return custom;
      return MaterialPageRoute<dynamic>(
        settings: settings,
        builder: (BuildContext context) => _defaultPage(context, fullPath),
      );
    }

    final WeaveRoute route = routeMatch.route;
    final List<String> chain = WeaveGateArguments.chainOf(settings.arguments);
    final Object? userArguments =
        WeaveGateArguments.unwrap(settings.arguments);
    final RouteSettings effectiveSettings =
        RouteSettings(name: settings.name, arguments: userArguments);

    final String? redirectPath = _resolveRedirect(route, routeMatch, chain);
    if (redirectPath != null) {
      return _createRouteFactory(
        RouteSettings(
          name: redirectPath,
          arguments: WeaveGateArguments(
            userArguments: userArguments,
            chain: <String>[...chain, fullPath],
          ),
        ),
      );
    }

    final WeaveParams weaveParams = WeaveParams.of(routeMatch.params);

    Widget buildContent(BuildContext context) {
      if (needsGate(route)) {
        return WeaveRouteGate(
          router: this,
          match: routeMatch,
          fullPath: fullPath,
          params: weaveParams,
          chain: chain,
        );
      }
      return buildPage(context, route, weaveParams);
    }

    if (route.transition.type != WeaveTransitionType.material) {
      return route.transition.buildRoute<dynamic>(
        Builder(builder: buildContent),
        settings: effectiveSettings,
      );
    }

    return MaterialPageRoute<dynamic>(
      settings: effectiveSettings,
      builder: buildContent,
    );
  }

  /// Resolve `redirect` declarativo, com teto de saltos.
  ///
  /// Usa o `rootElement` como contexto porque `onGenerateRoute` roda fora da
  /// árvore da rota. Consequência documentada: um `redirect` não pode
  /// depender de `InheritedWidget` da própria rota. Quando não há contexto
  /// (cold start), loga em vez de engolir silenciosamente.
  String? _resolveRedirect(
    WeaveRoute route,
    WeaveRouteMatch routeMatch,
    List<String> chain,
  ) {
    if (route.redirect == null) return null;

    if (chain.length >= maxRedirects) {
      _log('Redirect loop abortado (teto $maxRedirects): ${chain.join(' -> ')}');
      return null;
    }

    // ignore: invalid_use_of_protected_member
    final BuildContext? rootContext = WidgetsBinding.instance.rootElement;
    if (rootContext == null) {
      _log('redirect de ${route.path} ignorado: sem contexto raiz ainda.');
      return null;
    }

    final String? target = route.redirect!(
      rootContext,
      WeaveParams.of(routeMatch.params),
    );
    if (target == null) return null;

    if (chain.contains(target)) {
      _log('Redirect loop abortado: ${<String>[...chain, target].join(' -> ')}');
      return null;
    }
    return match(target) == null ? null : target;
  }

  /// Página padrão quando a rota não é encontrada.
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
          children: <Widget>[
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
