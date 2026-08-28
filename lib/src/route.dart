import 'package:flutter/material.dart';

import 'container.dart';
import 'guard.dart';
import 'middleware.dart';

/// Tipos de transição de página.
enum WeaveTransitionType {
  material,
  cupertino,
  fade,
  slideFromRight,
  slideFromBottom,
  scale,
  none,
}

/// Config de transição de página.
class WeaveTransition {
  final WeaveTransitionType type;
  final Duration? duration;
  final Curve? curve;
  final Widget Function(Animation<double>, Animation<double>, Widget)?
  customBuilder;

  const WeaveTransition({
    this.type = WeaveTransitionType.material,
    this.duration,
    this.curve,
    this.customBuilder,
  });

  static const material = WeaveTransition(type: WeaveTransitionType.material);
  static const cupertino = WeaveTransition(type: WeaveTransitionType.cupertino);
  static const fade = WeaveTransition(type: WeaveTransitionType.fade);
  static const slideRight = WeaveTransition(
    type: WeaveTransitionType.slideFromRight,
  );
  static const slideBottom = WeaveTransition(
    type: WeaveTransitionType.slideFromBottom,
  );
  static const scale = WeaveTransition(type: WeaveTransitionType.scale);
  static const none = WeaveTransition(type: WeaveTransitionType.none);

  /// Constrói um PageRouteBuilder com esta transição.
  ///
  /// [settings] carrega `name` e `arguments` para dentro da rota. Até a 2.0.0
  /// não era repassado: toda rota com transição custom chegava ao `Navigator`
  /// anônima, e nada que dependesse de `ModalRoute.of(context)?.settings`
  /// funcionava nela.
  PageRouteBuilder<T> buildRoute<T>(Widget page, {RouteSettings? settings}) {
    final Duration effectiveDuration = duration ??
        (type == WeaveTransitionType.none
            ? Duration.zero
            : const Duration(milliseconds: 300));
    final Curve effectiveCurve = curve ?? Curves.easeInOut;

    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: effectiveDuration,
      reverseTransitionDuration: effectiveDuration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (customBuilder != null) {
          return customBuilder!(animation, secondaryAnimation, child);
        }

        final curved = CurvedAnimation(
          parent: animation,
          curve: effectiveCurve,
        );

        switch (type) {
          case WeaveTransitionType.material:
          case WeaveTransitionType.none:
            return child;
          case WeaveTransitionType.cupertino:
          case WeaveTransitionType.slideFromRight:
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            );
          case WeaveTransitionType.slideFromBottom:
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 1.0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            );
          case WeaveTransitionType.fade:
            return FadeTransition(opacity: curved, child: child);
          case WeaveTransitionType.scale:
            return ScaleTransition(scale: curved, child: child);
        }
      },
    );
  }
}

/// Parâmetros da rota, tipados.
class WeaveParams {
  final Map<String, String> _params;

  const WeaveParams(this._params);

  /// Cópia defensiva: o mapa de origem pode continuar sendo mutado por quem
  /// o criou, e `WeaveParams` promete ser imutável.
  WeaveParams.of(Map<String, String> params)
      : _params = Map<String, String>.unmodifiable(params);

  /// Mapa raw dos parâmetros.
  Map<String, String> get raw => Map.unmodifiable(_params);

  /// Acesso direto como mapa.
  String? operator [](String key) => _params[key];

  /// Retorna string ou fallback.
  String getString(String key, {String fallback = ''}) =>
      _params[key] ?? fallback;

  /// Retorna int ou fallback. Retorna fallback se não for válido.
  int getInt(String key, {int fallback = 0}) {
    final value = _params[key];
    if (value == null) return fallback;
    return int.tryParse(value) ?? fallback;
  }

  /// Retorna double ou fallback.
  double getDouble(String key, {double fallback = 0.0}) {
    final value = _params[key];
    if (value == null) return fallback;
    return double.tryParse(value) ?? fallback;
  }

  /// Retorna bool ou fallback. Aceita 'true', '1', 'yes'.
  bool getBool(String key, {bool fallback = false}) {
    final value = _params[key];
    if (value == null) return fallback;
    return switch (value.toLowerCase()) {
      'true' || '1' || 'yes' => true,
      _ => fallback,
    };
  }

  /// Retorna lista (separada por delimitador). Ex: ?tags=a,b,c
  List<String> getList(
    String key, {
    String delimiter = ',',
    List<String> fallback = const [],
  }) {
    final value = _params[key];
    if (value == null || value.isEmpty) return fallback;
    return value
        .split(delimiter)
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// Retorna DateTime ou fallback.
  DateTime? getDateTime(String key) {
    final value = _params[key];
    if (value == null) return null;
    return DateTime.tryParse(value);
  }

  /// Verifica se a chave existe.
  bool contains(String key) => _params.containsKey(key);

  /// Número de parâmetros.
  int get length => _params.length;

  /// Se está vazio.
  bool get isEmpty => _params.isEmpty;

  /// Se não está vazio.
  bool get isNotEmpty => _params.isNotEmpty;

  /// Combina com outro mapa de parâmetros.
  WeaveParams merge(Map<String, String> other) {
    return WeaveParams({..._params, ...other});
  }

  @override
  String toString() => 'WeaveParams($_params)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WeaveParams &&
        other._params.length == _params.length &&
        other._params.entries.every(
          (e) => _params[e.key] == e.value,
        );
  }

  // `_params.hashCode` é a identidade do Map, então dois WeaveParams iguais
  // por `==` produziam hashes diferentes — contrato violado, e `Set` /
  // `Map` tratavam iguais como distintos. Hash sobre as entradas ordenadas.
  @override
  int get hashCode {
    final List<String> keys = _params.keys.toList()..sort();
    return Object.hashAll(<Object?>[
      for (final String key in keys) ...<Object?>[key, _params[key]],
    ]);
  }
}

/// Uma rota no Weave.
///
/// Cada rota tem um [path] (com `:param`), um builder, e opções
/// como [transition], [guards], [middlewares], [children] e [injectFactory].
class WeaveRoute {
  /// Caminho da rota, e.g. `/user/:id`.
  final String path;

  /// Nome opcional para navegação nomeada.
  final String? name;

  /// Builder que recebe [context] e [params] tipados.
  final Widget Function(BuildContext context, WeaveParams params) builder;

  /// Guards de autorização (executados antes de construir a página).
  final List<WeaveRouteGuard> guards;

  /// Middlewares (executados antes dos guards).
  final List<WeaveMiddleware> middlewares;

  /// Transição de página.
  final WeaveTransition transition;

  /// Redirect condicional. Retorna o path de destino ou null.
  final String? Function(BuildContext context, WeaveParams params)? redirect;

  /// Factory para lazy injection no container.
  final Widget Function(
    BuildContext context,
    WeaveParams params,
    WeaveContainer container,
  )?
  injectFactory;

  /// Rotas filhas (para rotas aninhadas).
  @Deprecated(
    'O WeaveRouter não consome `children`: a rota filha nunca é construída. '
    'Ver CHANGELOG 2.1.0.',
  )
  final List<WeaveRoute> children;

  /// Se é uma shell route (mantém layout pai).
  @Deprecated(
    'Shell routes não são consumidas pelo WeaveRouter. Ver CHANGELOG 2.1.0.',
  )
  final bool isShell;

  /// Builder do shell (usado quando [isShell] é true).
  @Deprecated(
    'Shell routes não são consumidas pelo WeaveRouter. Ver CHANGELOG 2.1.0.',
  )
  final Widget Function(BuildContext context, Widget child)? shellBuilder;

  /// Condição de existência da rota, avaliada a cada match.
  ///
  /// Retornando `false`, a rota se comporta como se não estivesse
  /// registrada: não casa, não aparece na busca por nome, e o path cai no
  /// tratamento de rota desconhecida.
  ///
  /// É a primitiva de "um codebase, N variantes" — white-label, feature
  /// flag, tier, região:
  ///
  /// ```dart
  /// WeaveRoute(
  ///   path: '/reseller',
  ///   when: () => brand.hasResellers,
  ///   builder: (_, _) => const ResellerPage(),
  /// )
  /// ```
  final bool Function()? when;

  /// Impede que o gate de guards embrulhe esta rota.
  ///
  /// Use no alvo de redirect de um guard (tipicamente `/login`): sem isso,
  /// um middleware **global** embrulha o próprio destino e o redirect vira
  /// laço estrutural.
  final bool skipGuards;

  /// Se a rota está ativa agora. Ver [when].
  bool get isEnabled => when == null || when!();

  const WeaveRoute({
    required this.path,
    this.name,
    required this.builder,
    this.guards = const [],
    this.middlewares = const [],
    this.transition = WeaveTransition.material,
    this.redirect,
    this.injectFactory,
    this.children = const [],
    @Deprecated('Ver CHANGELOG 2.1.0.') this.isShell = false,
    @Deprecated('Ver CHANGELOG 2.1.0.') this.shellBuilder,
    this.when,
    this.skipGuards = false,
  });

  /// Cria uma shell route (mantém layout pai enquanto navega filhos).
  @Deprecated(
    'O WeaveRouter não consome shell routes: a rota renderiza SizedBox vazio. '
    'Componha o shell dentro do builder da página. Ver CHANGELOG 2.1.0.',
  )
  // `const` preservado: removê-lo quebraria em tempo de compilação quem
  // declara `const WeaveRoute.shell(...)` na 2.0.0. A depreciação avisa; um
  // `assert(false)` derrubaria o `main()` de quem já convive com a tela
  // vazia hoje, e isso não cabe numa minor.
  const WeaveRoute.shell({
    required this.path,
    this.name,
    required this.shellBuilder,
    required this.children,
    this.builder = _defaultBuilder,
    this.guards = const [],
    this.middlewares = const [],
    this.transition = WeaveTransition.material,
    this.redirect,
    this.injectFactory,
    this.when,
    this.skipGuards = false,
  }) : isShell = true;

  static Widget _defaultBuilder(BuildContext context, WeaveParams params) =>
      const SizedBox();

  /// Cópia com valores sobrescritos.
  WeaveRoute copyWith({
    String? path,
    String? name,
    Widget Function(BuildContext, WeaveParams)? builder,
    List<WeaveRouteGuard>? guards,
    List<WeaveMiddleware>? middlewares,
    WeaveTransition? transition,
    String? Function(BuildContext, WeaveParams)? redirect,
    Widget Function(BuildContext, WeaveParams, WeaveContainer)? injectFactory,
    List<WeaveRoute>? children,
    bool? isShell,
    Widget Function(BuildContext, Widget)? shellBuilder,
    bool Function()? when,
    bool? skipGuards,
  }) {
    return WeaveRoute(
      path: path ?? this.path,
      name: name ?? this.name,
      builder: builder ?? this.builder,
      guards: guards ?? this.guards,
      middlewares: middlewares ?? this.middlewares,
      transition: transition ?? this.transition,
      redirect: redirect ?? this.redirect,
      injectFactory: injectFactory ?? this.injectFactory,
      children: children ?? this.children,
      // ignore: deprecated_member_use_from_same_package
      isShell: isShell ?? this.isShell,
      // ignore: deprecated_member_use_from_same_package
      shellBuilder: shellBuilder ?? this.shellBuilder,
      when: when ?? this.when,
      skipGuards: skipGuards ?? this.skipGuards,
    );
  }

  /// Verifica se o path corresponde a esta rota.
  ///
  /// Barra final é ignorada (`/user/42/` casa com `/user/:id`) — deep link
  /// chega com barra o tempo todo, e antes isso resultava em 404.
  bool matches(String routePath) {
    final String pathWithoutQuery = _normalize(routePath);
    return _toRegex(path).hasMatch(pathWithoutQuery);
  }

  static String _normalize(String routePath) {
    final String withoutQuery = routePath.split('?').first;
    if (withoutQuery.length > 1 && withoutQuery.endsWith('/')) {
      return withoutQuery.substring(0, withoutQuery.length - 1);
    }
    return withoutQuery;
  }

  /// Extrai parâmetros de path (`:param`).
  Map<String, String> extractParams(String routePath) {
    final params = <String, String>{};
    final String pathWithoutQuery = _normalize(routePath);
    final patternParts = _normalize(path).split('/');
    final routeParts = pathWithoutQuery.split('/');

    for (var i = 0; i < patternParts.length && i < routeParts.length; i++) {
      if (patternParts[i].startsWith(':')) {
        params[patternParts[i].substring(1)] = _decode(routeParts[i]);
      }
    }
    return params;
  }

  /// Path param chega percent-encoded (`/user/a%2Fb`) e a página precisa do
  /// valor real. `extractQueryParams` já decodifica via `splitQueryString`;
  /// sem isto os dois lados divergiam para a mesma entrada.
  static String _decode(String segment) {
    if (!segment.contains('%') && !segment.contains('+')) return segment;
    try {
      return Uri.decodeComponent(segment);
    } catch (_) {
      return segment;
    }
  }

  /// Extrai query params de uma URL.
  ///
  /// Usa [Uri.splitQueryString], que decodifica `+` como espaço e aceita
  /// flags sem valor (`?debug` vira `{'debug': ''}`). A implementação
  /// anterior lançava em URI truncada (`?q=100%`) e descartava flags.
  static Map<String, String> extractQueryParams(String routePath) {
    final int queryIndex = routePath.indexOf('?');
    if (queryIndex == -1) return <String, String>{};

    final String queryString = routePath.substring(queryIndex + 1);
    if (queryString.isEmpty) return <String, String>{};

    try {
      return Uri.splitQueryString(queryString);
    } catch (_) {
      // `splitQueryString` lança ArgumentError em URI truncada (`?q=100%`)
      // e FormatException em outros casos. Deep link malformado não pode
      // derrubar a navegação — vale a pena engolir os dois aqui.
      return <String, String>{};
    }
  }

  /// Retorna todos os parâmetros (path + query) como [WeaveParams].
  ///
  /// Path vence query em caso de colisão: `/user/:id` acessado como
  /// `/user/7?id=1` resolve `id` para `7`. O contrário deixaria um deep link
  /// sobrescrever o identificador que os guards vão inspecionar.
  WeaveParams extractAllParams(String routePath) {
    return WeaveParams.of(allParamsMap(routePath));
  }

  /// Mapa mutável com path + query. Path vence query.
  Map<String, String> allParamsMap(String routePath) => <String, String>{
        ...extractQueryParams(routePath),
        ...extractParams(routePath),
      };

  /// Busca uma rota filha que corresponda ao path.
  WeaveRouteMatch? matchChild(String fullPath) {
    if (children.isEmpty) return null;

    // Normaliza o path relativo ao parent
    final parentPath = path.endsWith('/') ? path : '$path/';
    if (!fullPath.startsWith(parentPath)) return null;

    final childPath = fullPath.substring(parentPath.length - 1);
    final normalizedChildPath = childPath.startsWith('/')
        ? childPath
        : '/$childPath';

    for (final child in children) {
      if (child.matches(normalizedChildPath)) {
        return WeaveRouteMatch(
          route: child,
          params: child.allParamsMap(normalizedChildPath),
        );
      }
    }
    return null;
  }

  static RegExp _toRegex(String path) {
    final String pathWithoutQuery = _normalize(path);
    final regexStr = pathWithoutQuery
        .split('/')
        .map((part) {
          if (part.startsWith(':')) return r'[^/]+';
          return RegExp.escape(part);
        })
        .join('/');
    return RegExp('^$regexStr\$');
  }

  @override
  String toString() =>
      'WeaveRoute($path${name != null ? ', name: $name' : ''})';
}

/// Resultado do match entre um path e uma [WeaveRoute].
class WeaveRouteMatch {
  /// A rota que correspondeu.
  final WeaveRoute route;

  /// Parâmetros extraídos do path.
  final Map<String, String> params;

  const WeaveRouteMatch({required this.route, required this.params});
}
