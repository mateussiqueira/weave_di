import 'package:flutter/material.dart';

import 'container_adapter.dart';
import 'route.dart';
import 'router.dart';

/// Extensões de navegação pra BuildContext.
///
/// Todos os métodos recebem [WeaveRouter] como parâmetro.
/// Não tem estado global — tudo explícito.
extension WeaveNavigation on BuildContext {
  /// Navega para uma rota registrada no router.
  void pushRoute(WeaveRouter router, String path, {Object? arguments}) async {
    final routeMatch = router.match(path);
    if (routeMatch == null) return;

    final route = routeMatch.route;

    // Verifica redirect
    if (route.redirect != null) {
      final redirectPath = route.redirect!(
        this,
        WeaveParams(routeMatch.params),
      );
      if (redirectPath != null) {
        return pushRoute(router, redirectPath, arguments: arguments);
      }
    }

    // Verifica guards e middlewares
    final allowed = await router.canActivateRoute(this, path, routeMatch);
    if (!allowed) return;
    if (!mounted) return;

    Widget buildPage(BuildContext context) {
      final weaveParams = WeaveParams(routeMatch.params);
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
      Navigator.of(this).push(
        route.transition.buildRoute(
          Builder(builder: (context) => buildPage(context)),
        ),
      );
      return;
    }

    Navigator.of(this).push(
      MaterialPageRoute(
        settings: RouteSettings(name: path, arguments: arguments),
        builder: (context) => buildPage(context),
      ),
    );
  }

  /// Substitui a rota atual por uma nova.
  void replaceRoute(
    WeaveRouter router,
    String path, {
    Object? arguments,
  }) async {
    final routeMatch = router.match(path);
    if (routeMatch == null) return;

    final route = routeMatch.route;
    final allowed = await router.canActivateRoute(this, path, routeMatch);
    if (!allowed) return;
    if (!mounted) return;

    Widget buildPage(BuildContext context) {
      final weaveParams = WeaveParams(routeMatch.params);
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
      Navigator.of(this).pushReplacement(
        route.transition.buildRoute(
          Builder(builder: (context) => buildPage(context)),
        ),
      );
      return;
    }

    Navigator.of(this).pushReplacement(
      MaterialPageRoute(
        settings: RouteSettings(name: path, arguments: arguments),
        builder: (context) => buildPage(context),
      ),
    );
  }

  /// Navega via nome da rota.
  void pushNamedRoute(
    WeaveRouter router,
    String name, {
    Object? arguments,
  }) {
    final route = router.routes.firstWhere(
      (r) => r.name == name,
      orElse: () => throw StateError('No route named $name found'),
    );
    pushRoute(router, route.path, arguments: arguments);
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
    Navigator.of(this).popUntil((route) => route.isFirst);
  }

  /// Substitui rota por nome.
  void pushReplacementNamed(
    WeaveRouter router,
    String name, {
    Object? arguments,
  }) {
    final route = router.routes.firstWhere(
      (r) => r.name == name,
      orElse: () => throw StateError('No route named $name found'),
    );
    replaceRoute(router, route.path, arguments: arguments);
  }

  /// Limpa stack e navega para uma nova rota.
  void clearStackAndPush(
    WeaveRouter router,
    String path, {
    Object? arguments,
  }) async {
    final routeMatch = router.match(path);
    if (routeMatch == null) return;

    final route = routeMatch.route;
    final allowed = await router.canActivateRoute(this, path, routeMatch);
    if (!allowed) return;
    if (!mounted) return;

    Widget buildPage(BuildContext context) {
      final weaveParams = WeaveParams(routeMatch.params);
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
      Navigator.of(this).pushAndRemoveUntil(
        route.transition.buildRoute(
          Builder(builder: (context) => buildPage(context)),
        ),
        (route) => false,
      );
      return;
    }

    Navigator.of(this).pushAndRemoveUntil(
      MaterialPageRoute(
        settings: RouteSettings(name: path, arguments: arguments),
        builder: (context) => buildPage(context),
      ),
      (route) => false,
    );
  }
}

/// Extensão para navegação global via router.
extension WeaveGlobalNavigation on WeaveRouter {
  /// Navega globalmente via router.
  void push(BuildContext context, String path, {Object? arguments}) {
    (context as Element).pushRoute(this, path, arguments: arguments);
  }
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
