// Regressões da auditoria adversarial da 2.1.0.
// Cada teste aqui corresponde a um defeito que foi REPRODUZIDO antes de ser
// corrigido. Se algum voltar a falhar, o defeito voltou.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave_di/weave_di.dart';

class _Svc {
  _Svc(this.tag);
  final String tag;
}

class _GlobalDep {}

/// Guard que só resolve quando o teste mandar.
class _ManualGuard implements WeaveRedirectingGuard {
  _ManualGuard(this.result);
  final WeaveGuardResult result;
  final Completer<void> gate = Completer<void>();

  @override
  Future<WeaveGuardResult> resolve(
    BuildContext c,
    String r,
    WeaveParams p,
    List<WeaveRoute> m,
  ) async {
    await gate.future;
    return result;
  }

  @override
  Future<bool> canActivate(
    BuildContext c,
    String r,
    WeaveParams p,
    List<WeaveRoute> m,
  ) async =>
      result is WeaveGuardAllow;
}

class _Observer extends NavigatorObserver {
  final List<String> events = <String>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previous) =>
      events.add('push ${route.settings.name}');

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previous) =>
      events.add('pop ${route.settings.name}');

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previous) =>
      events.add('remove ${route.settings.name}');

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      events.add('replace ${oldRoute?.settings.name} -> '
          '${newRoute?.settings.name}');
}

WeaveRoute _page(
  String path,
  String text, {
  List<WeaveGuard> guards = const <WeaveGuard>[],
  bool skipGuards = false,
  String? name,
}) =>
    WeaveRoute(
      path: path,
      name: name,
      guards: guards,
      skipGuards: skipGuards,
      builder: (_, WeaveParams p) => Scaffold(body: Text(text)),
    );

void main() {
  tearDown(() {
    WeaveLog.reset();
    WeaveContainerAdapter.global.reset();
  });

  // ───────────────────────────────────────────────────────────────────────
  group('B1 · gate não age em rota que saiu da pilha', () {
    testWidgets('pop antes da decisão cancela o redirect', (
      WidgetTester t,
    ) async {
      final _ManualGuard guard =
          _ManualGuard(const WeaveGuardResult.redirect('/login'));
      final _Observer obs = _Observer();
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          _page('/', 'home'),
          _page('/guarded', 'GUARDED', guards: <WeaveGuard>[guard]),
          _page('/login', 'LOGIN', skipGuards: true),
        ],
      );

      await t.pumpWidget(
        MaterialApp(
          onGenerateRoute: router.routeFactory,
          onGenerateInitialRoutes: router.onGenerateInitialRoutes,
          initialRoute: '/',
          navigatorObservers: <NavigatorObserver>[obs],
        ),
      );
      await t.pumpAndSettle();

      final NavigatorState nav = t.state(find.byType(Navigator));
      nav.pushNamed('/guarded');
      await t.pumpAndSettle();

      nav.pop();
      await t.pumpAndSettle();

      guard.gate.complete();
      await t.pumpAndSettle();

      expect(find.text('LOGIN'), findsNothing);
      expect(find.text('home'), findsOneWidget);
      expect(
        obs.events.where((String e) => e.contains('/login')),
        isEmpty,
        reason: 'o botão voltar não pode ser ignorado pelo guard',
      );
    });
  });

  group('I1 · redirect não rouba a tela de outra rota', () {
    testWidgets('rota enterrada é substituída no lugar dela', (
      WidgetTester t,
    ) async {
      final _ManualGuard guard =
          _ManualGuard(const WeaveGuardResult.redirect('/login'));
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          _page('/', 'home'),
          _page('/guarded', 'GUARDED', guards: <WeaveGuard>[guard]),
          _page('/other', 'OTHER', skipGuards: true),
          _page('/login', 'LOGIN', skipGuards: true),
        ],
      );

      await t.pumpWidget(
        MaterialApp(
          onGenerateRoute: router.routeFactory,
          onGenerateInitialRoutes: router.onGenerateInitialRoutes,
          initialRoute: '/',
        ),
      );
      await t.pumpAndSettle();

      final NavigatorState nav = t.state(find.byType(Navigator));
      nav.pushNamed('/guarded');
      await t.pumpAndSettle();
      nav.pushNamed('/other');
      await t.pumpAndSettle();

      guard.gate.complete();
      await t.pumpAndSettle();

      expect(
        find.text('OTHER'),
        findsOneWidget,
        reason: 'a tela do topo não pertence à rota guardada',
      );
      expect(find.text('LOGIN'), findsNothing);
    });
  });

  group('M1 · envelope do gate não vaza', () {
    testWidgets('onUnknownRoute recebe os arguments do usuário', (
      WidgetTester t,
    ) async {
      Object? seen = 'nao-chamado';
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          _page('/', 'home'),
          _page(
            '/guarded',
            'G',
            guards: <WeaveGuard>[
              WeaveGuard.custom(
                canActivate: (_, _, _, _) async => true,
              ),
            ],
          ),
        ],
        onUnknownRoute: (RouteSettings s) {
          seen = s.arguments;
          return MaterialPageRoute<void>(
            settings: s,
            builder: (_) => const Scaffold(body: Text('404')),
          );
        },
      );

      await t.pumpWidget(
        MaterialApp(
          onGenerateRoute: router.routeFactory,
          onGenerateInitialRoutes: router.onGenerateInitialRoutes,
          initialRoute: '/',
        ),
      );
      await t.pumpAndSettle();

      t.state<NavigatorState>(find.byType(Navigator))
          .pushNamed('/nao-existe', arguments: 42);
      await t.pumpAndSettle();

      expect(seen, 42);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('B2 · redirect de guard vale na navegação programática', () {
    testWidgets('pushRoute honra WeaveGuard.auth', (WidgetTester t) async {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          _page('/', 'home'),
          _page(
            '/admin',
            'ADMIN',
            guards: <WeaveGuard>[
              WeaveGuard.auth(isAuthenticated: (_) => false),
            ],
          ),
          _page('/login', 'LOGIN', skipGuards: true),
        ],
      );

      await t.pumpWidget(
        MaterialApp(
          onGenerateRoute: router.routeFactory,
          onGenerateInitialRoutes: router.onGenerateInitialRoutes,
          initialRoute: '/',
        ),
      );
      await t.pumpAndSettle();

      t.element(find.text('home')).pushRoute<void>(router, '/admin');
      await t.pumpAndSettle();

      expect(find.text('ADMIN'), findsNothing);
      expect(
        find.text('LOGIN'),
        findsOneWidget,
        reason: 'antes o redirect era descartado e virava no-op mudo',
      );
    });

    testWidgets('laço de redirect na extensão aborta', (WidgetTester t) async {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          _page('/', 'home'),
          _page(
            '/a',
            'A',
            guards: <WeaveGuard>[
              WeaveGuard.auth(isAuthenticated: (_) => false, loginPath: '/b'),
            ],
          ),
          _page(
            '/b',
            'B',
            guards: <WeaveGuard>[
              WeaveGuard.auth(isAuthenticated: (_) => false, loginPath: '/a'),
            ],
          ),
        ],
      );

      await t.pumpWidget(
        MaterialApp(
          onGenerateRoute: router.routeFactory,
          onGenerateInitialRoutes: router.onGenerateInitialRoutes,
          initialRoute: '/',
        ),
      );
      await t.pumpAndSettle();

      final String? result =
          await t.element(find.text('home')).pushRoute<String>(router, '/a');
      await t.pumpAndSettle();

      expect(result, isNull);
      expect(find.text('home'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────

  // ───────────────────────────────────────────────────────────────────────
  group('B4 · reinstalar módulo devolve container vivo', () {
    test('disposeContainer + install resolve pelo pai de novo', () {
      WeaveContainerAdapter.global.bindSingleton<_GlobalDep>(_GlobalDep.new);
      final WeaveModule m = WeaveModule(
        name: 'auth',
        binds: <WeaveBind>[
          (WeaveContainer c) => c.bindSingleton<_Svc>(() => _Svc('mod')),
        ],
      );

      m.install();
      expect(m.container.get<_Svc>().tag, 'mod');
      expect(m.container.get<_GlobalDep>(), isNotNull);

      m.disposeContainer();
      m.install();

      expect(m.container.get<_Svc>().tag, 'mod');
      expect(
        m.container.get<_GlobalDep>(),
        isNotNull,
        reason: 'container reinstalado precisa continuar enxergando o pai',
      );
    });

    test('global.reset seguido de install também se recupera', () {
      final WeaveModule m = WeaveModule(
        name: 'feat',
        binds: <WeaveBind>[
          (WeaveContainer c) => c.bindSingleton<_Svc>(() => _Svc('x')),
        ],
      );
      m.install();
      WeaveContainerAdapter.global.reset();
      m.disposeContainer();
      m.install();

      expect(m.container.get<_Svc>().tag, 'x');
    });
  });

  group('I5 · onInit não roda duas vezes', () {
    test('installAll repetido não reinicializa', () async {
      final _Counting a = _Counting('a');
      final _Counting b = _Counting('b');
      final WeaveModuleRegistry registry = WeaveModuleRegistry()..register(a);

      await registry.installAll();
      registry.register(b);
      await registry.installAll();

      expect(a.inits, 1);
      expect(b.inits, 1);
    });
  });

  group('M4 · disposeAll ignora módulo nunca instalado', () {
    test('onDispose não roda em quem não instalou', () async {
      final _Counting m = _Counting('m');
      final WeaveModuleRegistry registry = WeaveModuleRegistry()..register(m);
      await registry.disposeAll();
      expect(m.disposes, 0);
    });
  });

  group('M3 · módulo nunca instalado não vaza escopo', () {
    test('disposeContainer sem install é no-op', () {
      final WeaveModule m = WeaveModule(name: 'nunca');
      expect(m.disposeContainer, returnsNormally);
      expect(m.isInstalled, isFalse);
    });
  });

  group('M5 · nome duplicado via imports é erro', () {
    test('dois módulos distintos com o mesmo nome no grafo', () {
      final WeaveModule a = WeaveModule(name: 'dup');
      final WeaveModule b = WeaveModule(name: 'dup');
      final WeaveModule root =
          WeaveModule(name: 'root', imports: <WeaveModule>[a, b]);

      expect(
        root.install,
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('dup'),
          ),
        ),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('I6 · disposeScope tolera dispose redundante', () {
    test('duas chamadas seguidas não lançam', () {
      final WeaveContainerAdapter root = WeaveContainerAdapter.create(name: 'r');
      final WeaveContainerAdapter scope = root.createScopeNamed('s');
      root.disposeScope(scope);
      expect(() => root.disposeScope(scope), returnsNormally);
    });

    test('dispose após reset do pai não lança', () {
      final WeaveContainerAdapter root = WeaveContainerAdapter.create(name: 'r');
      final WeaveContainerAdapter scope = root.createScopeNamed('s');
      root.reset();
      expect(() => root.disposeScope(scope), returnsNormally);
    });
  });

  group('I7 · reset dispara onDispose e limpa netos', () {
    test('onDispose do escopo roda e o neto é limpo', () {
      bool disposed = false;
      final WeaveContainerAdapter root = WeaveContainerAdapter.create(name: 'r');
      final WeaveContainer child =
          root.createScope(onDispose: () => disposed = true);
      final WeaveContainer grand = child.createScope();
      grand.bindSingleton<_Svc>(() => _Svc('g'));

      root.reset();

      expect(disposed, isTrue);
      expect(grand.tryGet<_Svc>(), isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('I2 · path param decodificado', () {
    test('round-trip de valor com espaço e barra', () {
      final WeaveRoute route = _page('/user/:id', 'u');
      expect(route.extractParams('/user/joao%20silva')['id'], 'joao silva');
      expect(route.extractParams('/user/a%2Fb')['id'], 'a/b');
      expect(route.extractParams('/user/42')['id'], '42');
    });

    test('percent truncado não lança', () {
      final WeaveRoute route = _page('/user/:id', 'u');
      expect(route.extractParams('/user/100%')['id'], '100%');
    });

    testWidgets('valor navegado por nome chega íntegro na página', (
      WidgetTester t,
    ) async {
      String received = '';
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          _page('/', 'home'),
          WeaveRoute(
            path: '/user/:id',
            name: 'user',
            builder: (_, WeaveParams p) {
              received = p.getString('id');
              return const Scaffold(body: Text('user'));
            },
          ),
        ],
      );

      await t.pumpWidget(
        MaterialApp(
          onGenerateRoute: router.routeFactory,
          onGenerateInitialRoutes: router.onGenerateInitialRoutes,
          initialRoute: '/',
        ),
      );
      await t.pumpAndSettle();

      t.element(find.text('home')).pushNamedRoute<void>(
        router,
        'user',
        params: <String, String>{'id': 'joao silva'},
      );
      await t.pumpAndSettle();

      expect(received, 'joao silva');
    });
  });

  group('I3 / M7 · params faltando ou vazios lançam', () {
    testWidgets('param ausente é ArgumentError', (WidgetTester t) async {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[_page('/', 'home'), _page('/u/:id', 'u', name: 'u')],
      );
      await t.pumpWidget(
        MaterialApp(
          onGenerateRoute: router.routeFactory,
          onGenerateInitialRoutes: router.onGenerateInitialRoutes,
          initialRoute: '/',
        ),
      );
      await t.pumpAndSettle();
      final BuildContext ctx = t.element(find.text('home'));

      expect(
        () => ctx.pushNamedRoute<void>(router, 'u'),
        throwsArgumentError,
      );
    });

    testWidgets('param vazio também é ArgumentError, não silêncio', (
      WidgetTester t,
    ) async {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[_page('/', 'home'), _page('/u/:id', 'u', name: 'u')],
      );
      await t.pumpWidget(
        MaterialApp(
          onGenerateRoute: router.routeFactory,
          onGenerateInitialRoutes: router.onGenerateInitialRoutes,
          initialRoute: '/',
        ),
      );
      await t.pumpAndSettle();
      final BuildContext ctx = t.element(find.text('home'));

      expect(
        () => ctx.pushNamedRoute<void>(
          router,
          'u',
          params: <String, String>{'id': ''},
        ),
        throwsArgumentError,
      );
    });
  });

  group('M2 · segmento estático com ":" é navegável por nome', () {
    testWidgets('/at/12:30 não é confundido com param', (
      WidgetTester t,
    ) async {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          _page('/', 'home'),
          _page('/at/12:30', 'MEIO-DIA', name: 'meiodia'),
        ],
      );
      await t.pumpWidget(
        MaterialApp(
          onGenerateRoute: router.routeFactory,
          onGenerateInitialRoutes: router.onGenerateInitialRoutes,
          initialRoute: '/',
        ),
      );
      await t.pumpAndSettle();

      t.element(find.text('home')).pushNamedRoute<void>(router, 'meiodia');
      await t.pumpAndSettle();

      expect(find.text('MEIO-DIA'), findsOneWidget);
    });
  });
}


class _Counting extends WeaveModule {
  _Counting(String name) : super(name: name);

  int inits = 0;
  int disposes = 0;

  @override
  Future<void> onInit() async => inits++;

  @override
  Future<void> onDispose() async => disposes++;
}
