import 'package:flutter/material.dart';

import 'guard.dart';
import 'route.dart';
import 'router.dart';

/// Envelope interno que carrega a cadeia de redirects já visitada.
///
/// Fica em `RouteSettings.arguments` durante o trânsito e é desembrulhado
/// antes de chegar na página, de modo que o `arguments` visto pelo usuário
/// continua sendo o dele.
class WeaveGateArguments {
  const WeaveGateArguments({required this.userArguments, required this.chain});

  /// O `arguments` original de quem navegou.
  final Object? userArguments;

  /// Paths já visitados nesta cadeia de redirects.
  final List<String> chain;

  /// Desembrulha, se for um envelope.
  static Object? unwrap(Object? arguments) => arguments is WeaveGateArguments
      ? arguments.userArguments
      : arguments;

  /// Cadeia embutida, ou vazia.
  static List<String> chainOf(Object? arguments) =>
      arguments is WeaveGateArguments ? arguments.chain : const <String>[];
}

enum _GatePhase { pending, allowed, blocked }

/// Roda guards e middlewares antes de deixar a página existir.
///
/// `onGenerateRoute` precisa devolver um `Route` de forma síncrona, mas
/// `canActivateRoute` é assíncrono. O gate resolve isso ocupando o lugar da
/// página: monta um placeholder, decide fora do frame de build, e só então
/// troca pelo conteúdo real — ou tira a própria rota da pilha.
class WeaveRouteGate extends StatefulWidget {
  const WeaveRouteGate({
    super.key,
    required this.router,
    required this.match,
    required this.fullPath,
    required this.params,
    required this.chain,
  });

  final WeaveRouter router;
  final WeaveRouteMatch match;
  final String fullPath;
  final WeaveParams params;
  final List<String> chain;

  @override
  State<WeaveRouteGate> createState() => _WeaveRouteGateState();
}

class _WeaveRouteGateState extends State<WeaveRouteGate> {
  _GatePhase _phase = _GatePhase.pending;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Post-frame, não `build` nem `didChangeDependencies`: `ModalRoute.of`
    // é ilegal em `initState`, e rodar guard em `build` reexecutaria a cada
    // mudança de tema, locale ou teclado.
    WidgetsBinding.instance.addPostFrameCallback((_) => _decide());
  }

  Future<void> _decide() async {
    if (_started) return;
    _started = true;

    final NavigatorState navigator = Navigator.of(context);
    final ModalRoute<dynamic>? self = ModalRoute.of(context);

    final WeaveGuardResult result = await widget.router.resolveGuards(
      context,
      widget.fullPath,
      widget.match,
    );

    if (!mounted) return;

    switch (result) {
      case WeaveGuardAllow():
        setState(() => _phase = _GatePhase.allowed);
      case WeaveGuardRedirect(:final String path, :final Object? arguments):
        _redirect(navigator, self, path, arguments);
      case WeaveGuardBlock(:final String? reason):
        widget.router.log(
          'Blocked: ${widget.fullPath}${reason == null ? '' : ' ($reason)'}',
        );
        _terminate(navigator, self);
    }
  }

  void _redirect(
    NavigatorState navigator,
    ModalRoute<dynamic>? self,
    String target,
    Object? arguments,
  ) {
    final List<String> chain = <String>[...widget.chain, widget.fullPath];

    if (chain.contains(target) || chain.length >= widget.router.maxRedirects) {
      widget.router.log(
        'Redirect loop abortado: ${<String>[...chain, target].join(' -> ')}',
      );
      _terminate(navigator, self);
      return;
    }

    navigator.pushNamed<void>(
      target,
      arguments: WeaveGateArguments(userArguments: arguments, chain: chain),
    );
    // Remoção por identidade. `pushReplacement` miraria o topo da pilha, que
    // pode não ser esta rota se algo foi empurrado durante o await.
    if (self != null) navigator.removeRoute(self);
  }

  void _terminate(NavigatorState navigator, ModalRoute<dynamic>? self) {
    if (self != null && navigator.canPop()) {
      navigator.removeRoute(self);
      return;
    }
    // Primeira rota da pilha: não há para onde voltar. Estado bloqueado é
    // terminal e visível — nunca um pending eterno de tela vazia.
    setState(() => _phase = _GatePhase.blocked);
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _GatePhase.allowed:
        return widget.router.buildPage(
          context,
          widget.match.route,
          widget.params,
        );
      case _GatePhase.blocked:
        return widget.router.buildBlocked(context);
      case _GatePhase.pending:
        return widget.router.buildPending(context);
    }
  }
}
