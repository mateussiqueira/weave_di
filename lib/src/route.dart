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
  PageRouteBuilder<T> buildRoute<T>(Widget page) {
    final effectiveDuration = duration ?? const Duration(milliseconds: 300);
    final effectiveCurve = curve ?? Curves.easeInOut;

    return PageRouteBuilder<T>(
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

  @override
  int get hashCode => _params.hashCode;
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
  final List<WeaveRoute> children;

  /// Se é uma shell route (mantém layout pai).
  final bool isShell;

  /// Builder do shell (usado quando [isShell] é true).
  final Widget Function(BuildContext context, Widget child)? shellBuilder;

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
    this.isShell = false,
    this.shellBuilder,
  });

  /// Cria uma shell route (mantém layout pai enquanto navega filhos).
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
      isShell: isShell ?? this.isShell,
      shellBuilder: shellBuilder ?? this.shellBuilder,
    );
  }

  /// Verifica se o path corresponde a esta rota.
  bool matches(String routePath) {
    final pathWithoutQuery = routePath.split('?').first;
    final pattern = _toRegex(path);
    return pattern.hasMatch(pathWithoutQuery);
  }

  /// Extrai parâmetros de path (`:param`).
  Map<String, String> extractParams(String routePath) {
    final params = <String, String>{};
    final pathWithoutQuery = routePath.split('?').first;
    final patternParts = path.split('/');
    final routeParts = pathWithoutQuery.split('/');

    for (var i = 0; i < patternParts.length && i < routeParts.length; i++) {
      if (patternParts[i].startsWith(':')) {
        params[patternParts[i].substring(1)] = routeParts[i];
      }
    }
    return params;
  }

  /// Extrai query params de uma URL.
  static Map<String, String> extractQueryParams(String routePath) {
    final queryParams = <String, String>{};
    final queryIndex = routePath.indexOf('?');
    if (queryIndex == -1) return queryParams;

    final queryString = routePath.substring(queryIndex + 1);
    final pairs = queryString.split('&');

    for (final pair in pairs) {
      final equalIndex = pair.indexOf('=');
      if (equalIndex > 0) {
        final key = Uri.decodeComponent(pair.substring(0, equalIndex));
        final value = Uri.decodeComponent(pair.substring(equalIndex + 1));
        queryParams[key] = value;
      }
    }
    return queryParams;
  }

  /// Retorna todos os parâmetros (path + query) como [WeaveParams].
  WeaveParams extractAllParams(String routePath) {
    final pathParams = extractParams(routePath);
    final queryParams = extractQueryParams(routePath);
    return WeaveParams({...pathParams, ...queryParams});
  }

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
          params: child.extractParams(normalizedChildPath),
        );
      }
    }
    return null;
  }

  static RegExp _toRegex(String path) {
    final pathWithoutQuery = path.split('?').first;
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
