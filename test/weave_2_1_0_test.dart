import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave_di/weave_di.dart';

// ─────────────────────────────────────────────────────────────────────────
// Apoio
// ─────────────────────────────────────────────────────────────────────────

class _Svc {
  _Svc(this.tag);
  final String tag;
}

class _SpyMiddleware implements WeaveMiddleware {
  _SpyMiddleware({this.allow = true});
  final bool allow;
  int navigateCalls = 0;
  int matchedCalls = 0;

  @override
  Future<bool> onNavigate(BuildContext c, String p, WeaveParams params) async {
    navigateCalls++;
    return allow;
  }

  @override
  void onRouteMatched(BuildContext c, WeaveRouteMatch m) => matchedCalls++;
}

class _RedirectGuard implements WeaveRedirectingGuard {
  _RedirectGuard(this.target);
  final String target;
  int calls = 0;

  @override
  Future<WeaveGuardResult> resolve(
    BuildContext c,
    String r,
    WeaveParams p,
    List<WeaveRoute> m,
  ) async {
    calls++;
    return WeaveGuardResult.redirect(target);
  }

  @override
  Future<bool> canActivate(
    BuildContext c,
    String r,
    WeaveParams p,
    List<WeaveRoute> m,
  ) async =>
      false;
}

Widget _app(WeaveRouter router, {String initial = '/'}) => MaterialApp(
      onGenerateRoute: router.routeFactory,
      onGenerateInitialRoutes: router.onGenerateInitialRoutes,
      initialRoute: initial,
    );

WeaveRoute _page(
  String path,
  String text, {
  List<WeaveGuard> guards = const <WeaveGuard>[],
  List<WeaveMiddleware> middlewares = const <WeaveMiddleware>[],
  bool Function()? when,
  bool skipGuards = false,
  WeaveTransition transition = WeaveTransition.material,
  String? name,
}) =>
    WeaveRoute(
      path: path,
      name: name,
      guards: guards,
      middlewares: middlewares,
      when: when,
      skipGuards: skipGuards,
      transition: transition,
      builder: (_, _) => Scaffold(body: Text(text)),
    );

void main() {
  tearDown(() {
    WeaveLog.reset();
    WeaveContainerAdapter.global.reset();
  });

  // ───────────────────────────────────────────────────────────────────────
  group('A1 · logging', () {
    test('silencioso por padrão', () {
      final List<String> lines = <String>[];
      WeaveLog.logger = lines.add;
      WeaveLog.reset();

      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'q');
      c.bindSingleton<_Svc>(() => _Svc('x'));
      c.get<_Svc>();

      expect(lines, isEmpty);
    });

    test('escreve quando o logger global é atribuído', () {
      final List<String> lines = <String>[];
      WeaveLog.logger = lines.add;

      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'l');
      c.bindSingleton<_Svc>(() => _Svc('x'));
      c.get<_Svc>();

      expect(lines.any((String l) => l.contains('Resolved')), isTrue);
      expect(lines.every((String l) => l.startsWith('[Weave:l]')), isTrue);
    });

    test('logger do container tem precedência sobre o global', () {
      final List<String> global = <String>[];
      final List<String> local = <String>[];
      WeaveLog.logger = global.add;

      WeaveContainerAdapter.create(name: 'p', logger: local.add)
        ..bindSingleton<_Svc>(() => _Svc('x'))
        ..get<_Svc>();

      expect(local, isNotEmpty);
      expect(global, isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('A6 · unbind limpa override', () {
    test('depois de unbind o tipo fica irresolvível', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'u');
      c.bindSingleton<_Svc>(() => _Svc('real'));
      c.overrideFactory<_Svc>(() => _Svc('override'));
      c.unbind<_Svc>();
      expect(c.tryGet<_Svc>(), isNull);
    });
  });

  group('G3 · detecção de ciclo sobrevive a tryGet', () {
    test('ciclo através de tryGet não vira recursão infinita', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'cy');
      c.bindLazy<_Svc>(() {
        c.tryGet<_Svc>();
        return _Svc('a');
      });
      // Antes, o clear() da pilha desarmava a detecção e isso estourava
      // em StackOverflow.
      expect(c.get<_Svc>().tag, 'a');
    });

    test('ciclo direto continua sendo reportado', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'cy2');
      c.bindLazy<_Svc>(() => c.get<_Svc>());
      expect(
        () => c.get<_Svc>(),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('Circular dependency'),
          ),
        ),
      );
    });
  });

  group('escopos', () {
    test('disposeScope é recursivo', () {
      final WeaveContainerAdapter root = WeaveContainerAdapter.create(name: 'r');
      final WeaveContainerAdapter child = root.createScopeNamed('c');
      final WeaveContainerAdapter grand = child.createScopeNamed('g');
      grand.bindSingleton<_Svc>(() => _Svc('g'));

      root.disposeScope(child);
      expect(grand.tryGet<_Svc>(), isNull);
    });

    test('escopo nomeado aparece no nome do container', () {
      final WeaveContainerAdapter root = WeaveContainerAdapter.create(name: 'r');
      expect(root.createScopeNamed('auth').name, 'r.auth');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('WeaveParams · contrato de == / hashCode', () {
    // `const` aqui invalidaria os dois testes: o Dart canonicaliza literais
    // const, então `a` e `b` seriam o MESMO objeto e o hash bateria por
    // identidade, não por conteúdo. Precisam ser instâncias distintas.
    // ignore_for_file: prefer_const_constructors
    test('iguais por conteúdo têm o mesmo hashCode', () {
      final WeaveParams a = WeaveParams(<String, String>{'x': '1', 'y': '2'});
      final WeaveParams b = WeaveParams(<String, String>{'y': '2', 'x': '${1}'});
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('Set colapsa duplicatas', () {
      final WeaveParams a = WeaveParams(<String, String>{'x': '1'});
      final WeaveParams b = WeaveParams(<String, String>{'x': '${1}'});
      expect(<WeaveParams>{a, b}, hasLength(1));
    });

    test('WeaveParams.of copia defensivamente', () {
      final Map<String, String> source = <String, String>{'x': '1'};
      final WeaveParams params = WeaveParams.of(source);
      source['x'] = 'mutado';
      expect(params.getString('x'), '1');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('A7 · query params', () {
    final WeaveRouter router = WeaveRouter(
      routes: <WeaveRoute>[
        _page('/search', 'search'),
        _page('/user/:id', 'user'),
      ],
    );

    test('match preserva query — o caso que a README documenta', () {
      final WeaveParams p = WeaveParams.of(router.match('/search?q=hello&page=2')!.params);
      expect(p.getString('q'), 'hello');
      expect(p.getInt('page'), 2);
    });

    test('path vence query em colisão', () {
      final WeaveParams p = WeaveParams.of(router.match('/user/7?id=1')!.params);
      expect(p.getString('id'), '7');
    });

    test('flag sem valor vira string vazia', () {
      final WeaveParams p = WeaveParams.of(router.match('/search?debug')!.params);
      expect(p.contains('debug'), isTrue);
      expect(p.getString('debug'), '');
    });

    test('+ é decodificado como espaço', () {
      final WeaveParams p = WeaveParams.of(router.match('/search?q=hello+world')!.params);
      expect(p.getString('q'), 'hello world');
    });

    test('URI malformada não derruba a navegação', () {
      expect(router.match('/search?q=100%'), isNotNull);
      final WeaveParams p = WeaveParams.of(router.match('/search?q=100%')!.params);
      expect(p.isEmpty, isTrue);
    });

    test('params do match são mutáveis', () {
      final Map<String, String> params = router.match('/user/7')!.params;
      expect(() => params['extra'] = 'ok', returnsNormally);
    });
  });

  group('trailing slash', () {
    test('/user/42/ casa com /user/:id e extrai o param', () {
      final WeaveRoute route = _page('/user/:id', 'u');
      expect(route.matches('/user/42/'), isTrue);
      expect(route.extractParams('/user/42/')['id'], '42');
    });

    test('a raiz continua casando', () {
      expect(_page('/', 'root').matches('/'), isTrue);
    });
  });

  group('WeaveTransition', () {
    test('none tem duração zero', () {
      final PageRouteBuilder<void> r =
          WeaveTransition.none.buildRoute<void>(const SizedBox());
      expect(r.transitionDuration, Duration.zero);
    });

    test('settings chegam na rota', () {
      final PageRouteBuilder<void> r = WeaveTransition.fade.buildRoute<void>(
        const SizedBox(),
        settings: const RouteSettings(name: '/x', arguments: 42),
      );
      expect(r.settings.name, '/x');
      expect(r.settings.arguments, 42);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('A2 · guards em onGenerateRoute', () {
    testWidgets('deny bloqueia via pushNamed', (WidgetTester t) async {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          _page('/', 'publica'),
          _page('/secreta', 'SECRETO', guards: <WeaveGuard>[WeaveGuard.deny()]),
        ],
      );
      await t.pumpWidget(_app(router));
      final NavigatorState nav = t.state(find.byType(Navigator));
      nav.pushNamed('/secreta');
      await t.pumpAndSettle();

      expect(find.text('SECRETO'), findsNothing);
      expect(find.text('publica'), findsOneWidget);
    });

    testWidgets('deny bloqueia via deep link (rota inicial)', (
      WidgetTester t,
    ) async {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          _page('/secreta', 'SECRETO', guards: <WeaveGuard>[WeaveGuard.deny()]),
        ],
        guardBlockedBuilder: (_) => const Scaffold(body: Text('NEGADO')),
      );
      await t.pumpWidget(_app(router, initial: '/secreta'));
      await t.pumpAndSettle();

      expect(find.text('SECRETO'), findsNothing);
      expect(find.text('NEGADO'), findsOneWidget);
    });

    testWidgets('bloqueio sem pilha é terminal e visível, não pending eterno', (
      WidgetTester t,
    ) async {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          _page('/x', 'X', guards: <WeaveGuard>[WeaveGuard.deny()]),
        ],
        guardPendingBuilder: (_) => const Scaffold(body: Text('PENDING')),
        guardBlockedBuilder: (_) => const Scaffold(body: Text('BLOQUEADO')),
      );
      await t.pumpWidget(_app(router, initial: '/x'));
      await t.pumpAndSettle();

      expect(find.text('BLOQUEADO'), findsOneWidget);
      expect(find.text('PENDING'), findsNothing);
    });

    testWidgets('allow renderiza a página', (WidgetTester t) async {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          _page('/x', 'CONTEUDO', guards: <WeaveGuard>[WeaveGuard.allow()]),
        ],
      );
      await t.pumpWidget(_app(router, initial: '/x'));
      await t.pumpAndSettle();
      expect(find.text('CONTEUDO'), findsOneWidget);
    });

    testWidgets('middleware global é notificado e pode bloquear', (
      WidgetTester t,
    ) async {
      final _SpyMiddleware spy = _SpyMiddleware();
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[_page('/', 'home')],
        middlewares: <WeaveMiddleware>[spy],
      );
      await t.pumpWidget(_app(router));
      await t.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
      expect(spy.navigateCalls, 1);
      expect(spy.matchedCalls, 1);
    });

    testWidgets('middleware que nega bloqueia a rota', (WidgetTester t) async {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[_page('/', 'home')],
        middlewares: <WeaveMiddleware>[_SpyMiddleware(allow: false)],
        guardBlockedBuilder: (_) => const Scaffold(body: Text('NEGADO')),
      );
      await t.pumpWidget(_app(router));
      await t.pumpAndSettle();
      expect(find.text('NEGADO'), findsOneWidget);
    });

    testWidgets('redirect de guard vai para o destino', (WidgetTester t) async {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          _page('/secreta', 'SECRETO',
              guards: <WeaveGuard>[_RedirectGuard('/login')]),
          _page('/login', 'LOGIN', skipGuards: true),
        ],
      );
      await t.pumpWidget(_app(router, initial: '/secreta'));
      await t.pumpAndSettle();

      expect(find.text('LOGIN'), findsOneWidget);
      expect(find.text('SECRETO'), findsNothing);
    });

    testWidgets('laço de redirect aborta sem estourar a pilha', (
      WidgetTester t,
    ) async {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          _page('/a', 'A', guards: <WeaveGuard>[_RedirectGuard('/b')]),
          _page('/b', 'B', guards: <WeaveGuard>[_RedirectGuard('/a')]),
        ],
        guardBlockedBuilder: (_) => const Scaffold(body: Text('ABORTADO')),
      );
      await t.pumpWidget(_app(router, initial: '/a'));
      await t.pumpAndSettle();

      expect(find.text('ABORTADO'), findsOneWidget);
    });

    testWidgets('guard roda uma vez só, mesmo com rebuild', (
      WidgetTester t,
    ) async {
      final _RedirectGuard guard = _RedirectGuard('/login');
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          _page('/x', 'X', guards: <WeaveGuard>[guard]),
          _page('/login', 'LOGIN', skipGuards: true),
        ],
      );
      await t.pumpWidget(_app(router, initial: '/x'));
      await t.pumpAndSettle();
      await t.pumpWidget(_app(router, initial: '/x'));
      await t.pumpAndSettle();

      expect(guard.calls, 1);
    });

    testWidgets('skipGuards evita o gate', (WidgetTester t) async {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          _page('/x', 'X',
              guards: <WeaveGuard>[WeaveGuard.deny()], skipGuards: true),
        ],
      );
      await t.pumpWidget(_app(router, initial: '/x'));
      await t.pumpAndSettle();
      expect(find.text('X'), findsOneWidget);
    });

    test('needsGate: rota limpa em router sem middleware global não é gated', () {
      final WeaveRouter router = WeaveRouter(routes: <WeaveRoute>[_page('/', 'h')]);
      expect(router.needsGate(router.routes.first), isFalse);
    });

    test('needsGate: middleware global força o gate em toda rota', () {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[_page('/', 'h')],
        middlewares: <WeaveMiddleware>[_SpyMiddleware()],
      );
      expect(router.needsGate(router.routes.first), isTrue);
    });

    test('guardOnGenerateRoute: false desliga tudo', () {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          _page('/', 'h', guards: <WeaveGuard>[WeaveGuard.deny()]),
        ],
        guardOnGenerateRoute: false,
      );
      expect(router.needsGate(router.routes.first), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('B5 · rota desconhecida e rota inicial', () {
    testWidgets('onUnknownRoute customizado é usado', (WidgetTester t) async {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[_page('/', 'home')],
        onUnknownRoute: (RouteSettings s) => MaterialPageRoute<void>(
          settings: s,
          builder: (_) => const Scaffold(body: Text('404 CUSTOM')),
        ),
      );
      await t.pumpWidget(_app(router));
      final NavigatorState nav = t.state(find.byType(Navigator));
      nav.pushNamed('/nao-existe');
      await t.pumpAndSettle();

      expect(find.text('404 CUSTOM'), findsOneWidget);
    });

    test('onGenerateInitialRoutes gera exatamente uma rota', () {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[_page('/', 'h'), _page('/user/:id', 'u')],
      );
      expect(router.onGenerateInitialRoutes('/user/42'), hasLength(1));
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('B1 · rotas condicionais e composição', () {
    test('when falso remove a rota do match', () {
      bool enabled = false;
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[_page('/reseller', 'r', when: () => enabled)],
      );
      expect(router.match('/reseller'), isNull);
      enabled = true;
      expect(router.match('/reseller'), isNotNull);
    });

    test('when falso remove a rota da busca por nome', () {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          _page('/reseller', 'r', name: 'reseller', when: () => false),
        ],
      );
      expect(router.routeByName('reseller'), isNull);
    });

    testWidgets('rota desabilitada cai no tratamento de desconhecida', (
      WidgetTester t,
    ) async {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          _page('/', 'home'),
          _page('/reseller', 'RESELLER', when: () => false),
        ],
        onUnknownRoute: (RouteSettings s) => MaterialPageRoute<void>(
          settings: s,
          builder: (_) => const Scaffold(body: Text('INDISPONIVEL')),
        ),
      );
      await t.pumpWidget(_app(router));
      final NavigatorState nav = t.state(find.byType(Navigator));
      nav.pushNamed('/reseller');
      await t.pumpAndSettle();

      expect(find.text('RESELLER'), findsNothing);
      expect(find.text('INDISPONIVEL'), findsOneWidget);
    });

    test('mergeRoutes substitui in-place preservando a ordem', () {
      final List<WeaveRoute> base = <WeaveRoute>[
        _page('/a', 'a'),
        _page('/b', 'b'),
        _page('/c', 'c'),
      ];
      final List<WeaveRoute> merged = WeaveRouter.mergeRoutes(
        base,
        <WeaveRoute>[_page('/b', 'b-marca'), _page('/d', 'd')],
      );

      expect(merged.map((WeaveRoute r) => r.path), <String>['/a', '/b', '/c', '/d']);
      expect(merged[1].builder(_ctx(), const WeaveParams(<String, String>{})),
          isA<Widget>());
    });

    test('precedência por ordem de declaração sobrevive ao merge', () {
      final List<WeaveRoute> merged = WeaveRouter.mergeRoutes(
        <WeaveRoute>[_page('/user/new', 'novo'), _page('/user/:id', 'id')],
        <WeaveRoute>[_page('/user/:id', 'id-override')],
      );
      final WeaveRouter router = WeaveRouter(routes: merged);
      expect(router.match('/user/new')!.route.path, '/user/new');
    });

    test('WeaveRouter.merge compõe base + overrides', () {
      final WeaveRouter router = WeaveRouter.merge(
        base: <WeaveRoute>[_page('/a', 'a')],
        overrides: <WeaveRoute>[_page('/b', 'b')],
      );
      expect(router.routes, hasLength(2));
    });

    test('copyWith propaga when e skipGuards', () {
      final WeaveRoute route =
          _page('/x', 'x', when: () => false, skipGuards: true).copyWith();
      expect(route.isEnabled, isFalse);
      expect(route.skipGuards, isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('A9 · navegação devolve Future', () {
    testWidgets('pushRoute completa com o resultado do pop', (
      WidgetTester t,
    ) async {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[_page('/', 'home'), _page('/x', 'X')],
      );
      await t.pumpWidget(_app(router));
      await t.pumpAndSettle();
      final BuildContext ctx = t.element(find.text('home'));

      final Future<String?> pending = ctx.pushRoute<String>(router, '/x');
      await t.pumpAndSettle();
      expect(find.text('X'), findsOneWidget);

      Navigator.of(t.element(find.text('X'))).pop('resultado');
      await t.pumpAndSettle();
      expect(await pending, 'resultado');
    });

    testWidgets('rota inexistente completa com null', (WidgetTester t) async {
      final WeaveRouter router =
          WeaveRouter(routes: <WeaveRoute>[_page('/', 'home')]);
      await t.pumpWidget(_app(router));
      await t.pumpAndSettle();
      final BuildContext ctx = t.element(find.text('home'));

      expect(await ctx.pushRoute<String>(router, '/nada'), isNull);
    });
  });

  group('navegação nomeada com params', () {
    testWidgets('materializa :id no path', (WidgetTester t) async {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          _page('/', 'home'),
          WeaveRoute(
            path: '/user/:id',
            name: 'user',
            builder: (_, WeaveParams p) =>
                Scaffold(body: Text('user ${p.getString('id')}')),
          ),
        ],
      );
      await t.pumpWidget(_app(router));
      await t.pumpAndSettle();
      final BuildContext ctx = t.element(find.text('home'));

      ctx.pushNamedRoute<void>(
        router,
        'user',
        params: <String, String>{'id': '42'},
      );
      await t.pumpAndSettle();
      expect(find.text('user 42'), findsOneWidget);
    });

    // O caso de ArgumentError é coberto em weave_regression_test.dart, que
    // exercita a navegação de verdade. Aqui só a busca por nome.
    test('routeByName encontra a rota parametrizada', () {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[_page('/user/:id', 'u', name: 'user')],
      );
      expect(router.routeByName('user')?.path, '/user/:id');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('A3 · módulos', () {
    test('container do módulo enxerga o global', () {
      WeaveContainerAdapter.global.bindSingleton<String>(() => 'global');
      final WeaveModule m = WeaveModule(
        name: 'feature',
        binds: <WeaveBind>[(WeaveContainer c) => c.bindSingleton<_Svc>(() => _Svc('mod'))],
      );
      m.install();

      expect(m.container.get<_Svc>().tag, 'mod');
      expect(m.container.get<String>(), 'global');
    });

    test('router com container do módulo resolve os binds dele', () {
      final WeaveModule m = WeaveModule(
        name: 'feat',
        binds: <WeaveBind>[(WeaveContainer c) => c.bindSingleton<_Svc>(() => _Svc('mod'))],
      );
      m.install();

      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[_page('/', 'h')],
        container: m.container,
      );
      expect(router.effectiveContainer.get<_Svc>().tag, 'mod');
    });

    test('container é lazy: módulo não instalado não cria escopo', () {
      final int before = _globalScopeCount();
      WeaveModule(name: 'nunca-instalado');
      expect(_globalScopeCount(), before);
    });

    test('install é idempotente e preserva a instância', () {
      int builds = 0;
      final WeaveModule m = WeaveModule(
        name: 'idem',
        binds: <WeaveBind>[
          (WeaveContainer c) => c.bindLazy<_Svc>(() {
                builds++;
                return _Svc('x');
              }),
        ],
      );
      m.install();
      final _Svc first = m.container.get<_Svc>();
      m.install();
      expect(identical(m.container.get<_Svc>(), first), isTrue);
      expect(builds, 1);
    });

    test('módulo importado por dois é instalado uma vez', () {
      int installs = 0;
      final WeaveModule shared = WeaveModule(
        name: 'shared',
        binds: <WeaveBind>[
          (WeaveContainer c) {
            installs++;
            c.bindSingleton<_Svc>(() => _Svc('s'));
          },
        ],
      );
      final WeaveModule a =
          WeaveModule(name: 'a', imports: <WeaveModule>[shared]);
      final WeaveModule b =
          WeaveModule(name: 'b', imports: <WeaveModule>[shared]);

      final WeaveModuleRegistry registry = WeaveModuleRegistry()
        ..register(a)
        ..register(b);

      return registry.installAll().then((_) => expect(installs, 1));
    });

    test('ciclo de módulos é reportado', () {
      final List<WeaveModule> aImports = <WeaveModule>[];
      final WeaveModule a = WeaveModule(name: 'a', imports: aImports);
      final WeaveModule b = WeaveModule(name: 'b', imports: <WeaveModule>[a]);
      final WeaveModule c = WeaveModule(name: 'c', imports: <WeaveModule>[b]);
      aImports.add(c);

      expect(
        () => c.install(),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('Ciclo de módulos'),
          ),
        ),
      );
    });

    test('onInit roda uma vez por módulo, incluindo import não registrado',
        () async {
      final _CountingModule imported = _CountingModule('imp');
      final _CountingModule root =
          _CountingModule('root', imports: <WeaveModule>[imported]);

      await (WeaveModuleRegistry()..register(root)).installAll();

      expect(imported.inits, 1);
      expect(root.inits, 1);
    });

    test('nome duplicado no registry é erro', () {
      final WeaveModuleRegistry registry = WeaveModuleRegistry()
        ..register(WeaveModule(name: 'x'));
      expect(
        () => registry.register(WeaveModule(name: 'x')),
        throwsA(isA<StateError>()),
      );
    });

    test('allRoutes não duplica rota de módulo compartilhado', () {
      final WeaveModule shared = WeaveModule(
        name: 'shared',
        routes: <WeaveRoute>[_page('/s', 's')],
      );
      final WeaveModule a = WeaveModule(
        name: 'a',
        imports: <WeaveModule>[shared],
        routes: <WeaveRoute>[_page('/a', 'a')],
      );
      final WeaveModule b = WeaveModule(
        name: 'b',
        imports: <WeaveModule>[shared],
        routes: <WeaveRoute>[_page('/b', 'b')],
      );

      final WeaveModuleRegistry registry = WeaveModuleRegistry()
        ..register(a)
        ..register(b);

      expect(
        registry.allRoutes.map((WeaveRoute r) => r.path).toList()..sort(),
        <String>['/a', '/b', '/s'],
      );
    });

    test('disposeAll descarta o escopo, não só reseta', () async {
      final WeaveModule m = WeaveModule(
        name: 'd',
        binds: <WeaveBind>[(WeaveContainer c) => c.bindSingleton<_Svc>(() => _Svc('x'))],
      );
      final WeaveModuleRegistry registry = WeaveModuleRegistry()..register(m);
      await registry.installAll();
      expect(m.container.get<_Svc>().tag, 'x');

      await registry.disposeAll();
      expect(m.isInstalled, isFalse);
      expect(m.container.tryGet<_Svc>(), isNull);
    });
  });
}

int _globalScopeCount() {
  // Sem API pública para contar escopos; o proxy é o nome do próximo escopo.
  final WeaveContainerAdapter probe =
      WeaveContainerAdapter.global.createScopeNamed(null);
  final int index =
      int.parse(probe.name.split('scope').last);
  WeaveContainerAdapter.global.disposeScope(probe);
  return index;
}

BuildContext _ctx() => _FakeContext();

class _FakeContext extends StatelessElement {
  _FakeContext() : super(const _FakeWidget());
}

class _FakeWidget extends StatelessWidget {
  const _FakeWidget();
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _CountingModule extends WeaveModule {
  _CountingModule(String name, {super.imports = const <WeaveModule>[]})
      : super(name: name);

  int inits = 0;

  @override
  Future<void> onInit() async => inits++;
}

