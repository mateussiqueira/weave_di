import 'package:flutter/material.dart';

import 'guard.dart';
import 'route.dart';

/// Shell route pra layouts persistentes.
///
/// Mantém o shell (bottom nav, sidebar, etc.) e troca
/// só o conteúdo interno.
///
/// ```dart
/// WeaveShellRoute(
///   path: '/app',
///   shellBuilder: (context, child) => Scaffold(
///     body: child,
///     bottomNavigationBar: BottomNavigationBar(...),
///   ),
///   routes: [
///     WeaveRoute(path: '/home', builder: ...),
///     WeaveRoute(path: '/settings', builder: ...),
///   ],
/// )
/// ```
class WeaveShellRoute {
  final String path;
  final String? name;
  final Widget Function(BuildContext context, Widget child) shellBuilder;
  final List<WeaveRoute> routes;
  final List<WeaveGuard> guards;

  const WeaveShellRoute({
    required this.path,
    this.name,
    required this.shellBuilder,
    required this.routes,
    this.guards = const [],
  });

  /// Verifica se uma rota filha corresponde ao path fornecido.
  WeaveRouteMatch? matchChild(String fullPath) {
    final shellPath = path.endsWith('/') ? path : '$path/';
    if (!fullPath.startsWith(shellPath)) return null;

    final childPath = fullPath.substring(shellPath.length - 1);
    final normalizedChildPath = childPath.startsWith('/')
        ? childPath
        : '/$childPath';

    for (final route in routes) {
      if (route.matches(normalizedChildPath)) {
        return WeaveRouteMatch(
          route: route,
          params: route.extractParams(normalizedChildPath),
        );
      }
    }
    return null;
  }

  /// Constrói o shell com o conteúdo da rota filha.
  Widget build(BuildContext context, String fullPath, Widget child) {
    return shellBuilder(context, child);
  }
}

/// Widget que renderiza um shell route com navegação interna.
class WeaveShellOutlet extends StatefulWidget {
  final WeaveShellRoute shellRoute;
  final String currentPath;
  final Widget Function(BuildContext context, WeaveRouteMatch match)?
  childBuilder;

  const WeaveShellOutlet({
    super.key,
    required this.shellRoute,
    required this.currentPath,
    this.childBuilder,
  });

  @override
  State<WeaveShellOutlet> createState() => _WeaveShellOutletState();
}

class _WeaveShellOutletState extends State<WeaveShellOutlet> {
  @override
  Widget build(BuildContext context) {
    final match = widget.shellRoute.matchChild(widget.currentPath);

    if (match == null) {
      if (widget.shellRoute.routes.isNotEmpty) {
        final firstRoute = widget.shellRoute.routes.first;
        final firstMatch = WeaveRouteMatch(
          route: firstRoute,
          params: firstRoute.extractParams(widget.currentPath),
        );
        final child = widget.childBuilder != null
            ? widget.childBuilder!(context, firstMatch)
            : firstRoute.builder(context, WeaveParams(firstMatch.params));
        return widget.shellRoute.build(context, widget.currentPath, child);
      }
      return const SizedBox();
    }

    final child = widget.childBuilder != null
        ? widget.childBuilder!(context, match)
        : match.route.builder(context, WeaveParams(match.params));
    return widget.shellRoute.build(context, widget.currentPath, child);
  }
}
