import 'package:flutter/material.dart';

import 'gate.dart';
import 'route.dart';
import 'router.dart';

/// Extensões de navegação pra BuildContext.
///
/// Todos os métodos recebem [WeaveRouter] como parâmetro.
/// Não tem estado global — tudo explícito.
extension WeaveNavigation on BuildContext {
  /// Navega para uma rota registrada no router.
  ///
  /// O `Future` completa quando a rota é removida da pilha, com o valor do
  /// `pop`. Completa com `null` imediatamente se a rota não existir ou se um
  /// guard bloquear.
  Future<T?> pushRoute<T>(
    WeaveRouter router,
    String path, {
    Object? arguments,
  }) async {
    final _Resolved<T>? resolved =
        await _resolve<T>(router, path, arguments, const <String>[]);
    if (resolved == null) return null;
    return Navigator.of(this).push<T>(resolved.route);
  }

  /// Substitui a rota atual por uma nova.
  Future<T?> replaceRoute<T>(
    WeaveRouter router,
    String path, {
    Object? arguments,
  }) async {
    final _Resolved<T>? resolved =
        await _resolve<T>(router, path, arguments, const <String>[]);
    if (resolved == null) return null;
    return Navigator.of(this).pushReplacement<T, dynamic>(resolved.route);
  }

  /// Limpa a pilha e navega para uma nova rota.
  Future<T?> clearStackAndPush<T>(
    WeaveRouter router,
    String path, {
    Object? arguments,
  }) async {
    final _Resolved<T>? resolved =
        await _resolve<T>(router, path, arguments, const <String>[]);
    if (resolved == null) return null;
    return Navigator.of(this).pushAndRemoveUntil<T>(
      resolved.route,
      (Route<dynamic> _) => false,
    );
  }

  /// Navega via nome da rota.
  ///
  /// [params] materializa os `:segmentos` do path. Sem isso, uma rota
  /// `/user/:id` navegada por nome empurrava o path literal, com `:id` no
  /// lugar do valor.
  Future<T?> pushNamedRoute<T>(
    WeaveRouter router,
    String name, {
    Object? arguments,
    Map<String, String> params = const <String, String>{},
  }) {
    final WeaveRoute route = _byName(router, name);
    return pushRoute<T>(
      router,
      _materialize(route.path, params),
      arguments: arguments,
    );
  }

  /// Substitui a rota atual usando o nome da rota de destino.
  Future<T?> pushReplacementNamed<T>(
    WeaveRouter router,
    String name, {
    Object? arguments,
    Map<String, String> params = const <String, String>{},
  }) {
    final WeaveRoute route = _byName(router, name);
    return replaceRoute<T>(
      router,
      _materialize(route.path, params),
      arguments: arguments,
    );
  }

  /// Volta para a tela anterior.
  void popRoute([Object? result]) {
    if (Navigator.of(this).canPop()) {
      Navigator.of(this).pop(result);
    }
  }

  /// Retorna true se pode fazer pop.
  bool get canPopRoute => Navigator.of(this).canPop();

  /// Volta até a primeira rota.
  void popUntilRoot() {
    Navigator.of(this).popUntil((Route<dynamic> route) => route.isFirst);
  }

  WeaveRoute _byName(WeaveRouter router, String name) {
    final WeaveRoute? route = router.routeByName(name);
    if (route == null) throw StateError('No route named $name found');
    return route;
  }

  /// Roda redirect + guards e devolve a rota pronta, ou `null` se bloqueado.
  Future<_Resolved<T>?> _resolve<T>(
    WeaveRouter router,
    String path,
    Object? arguments,
    List<String> chain,
  ) async {
    final WeaveRouteMatch? routeMatch = router.match(path);
    if (routeMatch == null) return null;

    final WeaveRoute route = routeMatch.route;
    final WeaveParams params = WeaveParams.of(routeMatch.params);

    // `redirect` declarativo — agora nos três métodos, não só no push.
    if (route.redirect != null) {
      if (chain.length >= router.maxRedirects) {
        router.log('Redirect loop abortado (teto): ${chain.join(' -> ')}');
        return null;
      }
      final String? target = route.redirect!(this, params);
      if (target != null && !chain.contains(target)) {
        if (!mounted) return null;
        return _resolve<T>(
          router,
          target,
          arguments,
          <String>[...chain, path],
        );
      }
      if (target != null) {
        router.log(
          'Redirect loop abortado: ${<String>[...chain, target].join(' -> ')}',
        );
        return null;
      }
    }

    if (!mounted) return null;
    final bool allowed = await router.canActivateRoute(this, path, routeMatch);
    if (!allowed || !mounted) return null;

    Widget buildPage(BuildContext context) =>
        router.buildPage(context, route, params);

    final RouteSettings settings = RouteSettings(
      name: path,
      arguments: WeaveGateArguments.unwrap(arguments),
    );

    if (route.transition.type != WeaveTransitionType.material) {
      return _Resolved<T>(
        route.transition.buildRoute<T>(
          Builder(builder: buildPage),
          settings: settings,
        ),
      );
    }

    return _Resolved<T>(
      MaterialPageRoute<T>(settings: settings, builder: buildPage),
    );
  }

  static String _materialize(String path, Map<String, String> params) {
    if (!path.contains(':')) return path;

    final String result = path
        .split('/')
        .map((String part) {
          if (!part.startsWith(':')) return part;
          final String key = part.substring(1);
          final String? value = params[key];
          if (value == null) return part;
          return Uri.encodeComponent(value);
        })
        .join('/');

    if (result.contains(':')) {
      throw ArgumentError.value(
        params,
        'params',
        'Faltam parâmetros para o path "$path" (resultou em "$result")',
      );
    }
    return result;
  }
}

class _Resolved<T> {
  const _Resolved(this.route);
  final Route<T> route;
}

/// Extensão para navegação global via router.
extension WeaveGlobalNavigation on WeaveRouter {
  /// Navega globalmente via router.
  Future<T?> push<T>(
    BuildContext context,
    String path, {
    Object? arguments,
  }) =>
      context.pushRoute<T>(this, path, arguments: arguments);
}

/// Extensões para dialogs e modals.
extension WeaveDialogNavigation on BuildContext {
  /// Mostra um dialog.
  Future<T?> showWeaveDialog<T>({
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    bool useRootNavigator = true,
    Color? barrierColor,
  }) {
    return showDialog<T>(
      context: this,
      barrierDismissible: barrierDismissible,
      useRootNavigator: useRootNavigator,
      barrierColor: barrierColor,
      builder: builder,
    );
  }

  /// Mostra um bottom sheet.
  Future<T?> showWeaveModal<T>({
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    bool isDismissible = true,
    bool enableDrag = true,
    bool useSafeArea = false,
    Color? backgroundColor,
    ShapeBorder? shape,
    double? elevation,
  }) {
    return showModalBottomSheet<T>(
      context: this,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      useSafeArea: useSafeArea,
      backgroundColor: backgroundColor,
      shape: shape,
      elevation: elevation,
      builder: builder,
    );
  }

  /// Fecha o dialog/overlay atual.
  void popDialog<T>([T? result]) {
    if (Navigator.of(this, rootNavigator: true).canPop()) {
      Navigator.of(this, rootNavigator: true).pop(result);
    }
  }
}
