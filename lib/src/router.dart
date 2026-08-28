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
    this.stackAncestorsOnDeepLink = false,
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

  /// As rotas como foram declaradas — possivelmente uma árvore.
  final List<WeaveRoute> routes;

  final List<WeaveMiddleware> middlewares;

  List<WeaveRoute>? _flat;
  final Map<WeaveRoute, List<WeaveRoute>> _ancestors =
      Map<WeaveRoute, List<WeaveRoute>>.identity();

  /// A árvore achatada: uma entrada por rota, com path absoluto, guards e
  /// middlewares dos ancestrais já embutidos.
  ///
  /// É sobre esta lista que [match] e [routeByName] trabalham. Para uma
  /// declaração plana, é idêntica a [routes].
  List<WeaveRoute> get flatRoutes => _flat ??= _flatten();

  List<WeaveRoute> _flatten() {
    final List<WeaveRoute> out = <WeaveRoute>[];

    void walk(WeaveRoute route, String prefix, List<WeaveRoute> chain) {
      final String absolute = _joinPaths(prefix, route.path);

      // Rota de topo sem filhos é usada como veio — nada a herdar, nada a
      // reescrever. Mantém a identidade, o que importa para quem já guarda
      // referências às próprias rotas.
      final WeaveRoute effective = chain.isEmpty
          ? route
          : route.copyWith(
              path: absolute,
              // Guard e middleware de ancestral valem para a subárvore
              // inteira: proteger `/cadernos` protege `/cadernos/:id/gabarito`.
              //
              // Só o pai DIRETO entra: ele já acumulou os dele na própria
              // passagem. Somar a cadeia toda duplicaria o guard do avô no
              // neto, e um guard que roda duas vezes é um bug silencioso.
              guards: <WeaveRouteGuard>[
                ...chain.last.guards,
                ...route.guards,
              ],
              middlewares: <WeaveMiddleware>[
                ...chain.last.middlewares,
                ...route.middlewares,
              ],
            );

      out.add(effective);
      _ancestors[effective] = List<WeaveRoute>.unmodifiable(chain);

      for (final WeaveRoute child in route.children) {
        walk(child, absolute, <WeaveRoute>[...chain, effective]);
      }
    }

    for (final WeaveRoute route in routes) {
      walk(route, '', const <WeaveRoute>[]);
    }
    return List<WeaveRoute>.unmodifiable(out);
  }

  static String _joinPaths(String prefix, String path) {
    if (prefix.isEmpty) return path;
    final String left =
        prefix.endsWith('/') ? prefix.substring(0, prefix.length - 1) : prefix;
    final String right = path.startsWith('/') ? path : '/$path';
    return '$left$right';
  }

  /// Os ancestrais de uma rota achatada, do topo até o pai direto.
  ///
  /// Vazio para rota raiz. É o que dá breadcrumb sem cirurgia de string.
  List<WeaveRoute> ancestorsOf(WeaveRoute route) =>
      _ancestors[route] ?? const <WeaveRoute>[];

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

  /// Se um deep link em folha de hierarquia deve empilhar os ancestrais.
  ///
  /// Ligue em app hierárquico — web com URL, ou app organizado por módulos
  /// que possuem subárvores. Entrar direto em `/cadernos/7/gabarito` passa a
  /// montar a pilha `/cadernos` → `/cadernos/7` → `/cadernos/7/gabarito`, e o
  /// voltar sobe a árvore em vez de fechar o app.
  ///
  /// `false` por padrão: numa declaração plana não há ancestral a empilhar, e
  /// mudar o default alteraria o comportamento de quem já publicou.
  final bool stackAncestorsOnDeepLink;

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
    for (final WeaveRoute route in flatRoutes) {
      if (!route.isEnabled) continue;
      if (route.matches(path)) {
        _log('Matched: ${route.path} for path: $path');
        return WeaveRouteMatch(
          route: route,
          params: route.allParamsMap(path),
          ancestors: ancestorsOf(route),
        );
      }
    }
    _log('No match for path: $path');
    return null;
  }

  /// Busca uma rota pelo nome, respeitando [WeaveRoute.when].
  WeaveRoute? routeByName(String name) {
    for (final WeaveRoute route in flatRoutes) {
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
    Widget page = route.injectFactory != null
        ? route.injectFactory!(context, params, effectiveContainer)
        : route.builder(context, params);

    // Layout dos ancestrais, do mais interno para o mais externo: o shell da
    // loja envolve a página do produto, e o shell da seção envolve os dois.
    page = _wrapInLayouts(context, route, page);
    return page;
  }

  Widget _wrapInLayouts(
    BuildContext context,
    WeaveRoute route,
    Widget page,
  ) {
    Widget result = page;
    if (route.layoutBuilder != null) {
      result = route.layoutBuilder!(context, result);
    }
    final List<WeaveRoute> chain = ancestorsOf(route);
    for (final WeaveRoute ancestor in chain.reversed) {
      if (ancestor.layoutBuilder != null) {
        result = ancestor.layoutBuilder!(context, result);
      }
    }
    return result;
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
    if (!stackAncestorsOnDeepLink) {
      final Route<dynamic>? route =
          _createRouteFactory(RouteSettings(name: initialRoute));
      return <Route<dynamic>>[?route];
    }

    // Deep link em folha de hierarquia: empilha os ancestrais que existem,
    // para que o voltar (do Android ou do browser) suba a árvore em vez de
    // sair do app. `/cadernos/7/gabarito` vira /cadernos -> /cadernos/7 ->
    // /cadernos/7/gabarito. Segmento sem rota é pulado, não vira 404.
    final WeaveRouteMatch? leaf = match(initialRoute);
    if (leaf == null) {
      final Route<dynamic>? route =
          _createRouteFactory(RouteSettings(name: initialRoute));
      return <Route<dynamic>>[?route];
    }

    final String query = initialRoute.contains('?')
        ? initialRoute.substring(initialRoute.indexOf('?'))
        : '';
    final WeaveParams params = WeaveParams.of(leaf.params);

    final List<Route<dynamic>> stack = <Route<dynamic>>[];
    for (final WeaveRoute ancestor in leaf.ancestors) {
      final String? concrete = _concretize(ancestor.path, params);
      if (concrete == null) continue;
      final Route<dynamic>? route =
          _createRouteFactory(RouteSettings(name: concrete));
      if (route != null) stack.add(route);
    }

    final Route<dynamic>? leafRoute = _createRouteFactory(
      RouteSettings(name: '${_concretize(leaf.route.path, params) ?? initialRoute}$query'),
    );
    if (leafRoute != null) stack.add(leafRoute);

    return stack.isEmpty
        ? <Route<dynamic>>[?_createRouteFactory(RouteSettings(name: initialRoute))]
        : stack;
  }

  /// Substitui os `:segmentos` de um path pelos valores já conhecidos.
  /// Devolve `null` se algum parâmetro não estiver disponível.
  static String? _concretize(String pattern, WeaveParams params) {
    if (!pattern.contains(':')) return pattern;
    final List<String> parts = pattern.split('/');
    for (int i = 0; i < parts.length; i++) {
      final String part = parts[i];
      if (!part.startsWith(':')) continue;
      final String value = params.getString(part.substring(1));
      if (value.isEmpty) return null;
      parts[i] = Uri.encodeComponent(value);
    }
    return parts.join('/');
  }

  Route<dynamic>? _createRouteFactory(RouteSettings settings) {
    final String fullPath = settings.name ?? '/';
    // Desembrulha ANTES de qualquer ramo: o envelope é detalhe interno do
    // gate e não pode vazar para `onUnknownRoute` nem para a página.
    final List<String> chain = WeaveGateArguments.chainOf(settings.arguments);
    final Object? userArguments =
        WeaveGateArguments.unwrap(settings.arguments);
    final RouteSettings effectiveSettings =
        RouteSettings(name: settings.name, arguments: userArguments);

    final WeaveRouteMatch? routeMatch = match(fullPath);

    if (routeMatch == null) {
      final Route<dynamic>? custom = onUnknownRoute?.call(effectiveSettings);
      if (custom != null) return custom;
      return MaterialPageRoute<dynamic>(
        settings: effectiveSettings,
        builder: (BuildContext context) => _defaultPage(context, fullPath),
      );
    }

    final WeaveRoute route = routeMatch.route;

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
