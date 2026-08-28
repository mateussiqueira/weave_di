// Rotas hierárquicas — árvore declarada, achatada na construção do router.
// Os dois casos de referência: delivery (web, URL) e concursos (módulos).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave_di/weave_di.dart';

class _CountingGuard implements WeaveGuard {
  int calls = 0;

  @override
  Future<bool> canActivate(
    BuildContext c,
    String r,
    WeaveParams p,
    List<WeaveRoute> m,
  ) async {
    calls++;
    return true;
  }
}

Widget _txt(String label) => Scaffold(body: Text(label));

void main() {
  tearDown(WeaveLog.reset);

  // ── delivery: /estabelecimentos/:slug/produtos/:id ────────────────────
  group('delivery · árvore declarada vira path absoluto', () {
    WeaveRouter build() => WeaveRouter(
          routes: <WeaveRoute>[
            WeaveRoute(path: '/', builder: (_, _) => _txt('home')),
            WeaveRoute(
              path: '/estabelecimentos',
              name: 'lojas',
              builder: (_, _) => _txt('lista'),
              children: <WeaveRoute>[
                WeaveRoute(
                  path: '/:slug',
                  name: 'loja',
                  builder: (_, WeaveParams p) => _txt('loja ${p.getString('slug')}'),
                  children: <WeaveRoute>[
                    WeaveRoute(
                      path: '/categorias/:cat',
                      name: 'categoria',
                      builder: (_, WeaveParams p) =>
                          _txt('cat ${p.getString('cat')}'),
                    ),
                    WeaveRoute(
                      path: '/produtos/:id',
                      name: 'produto',
                      builder: (_, WeaveParams p) =>
                          _txt('produto ${p.getString('id')}'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        );

    test('paths absolutos são derivados da árvore', () {
      expect(
        build().flatRoutes.map((WeaveRoute r) => r.path),
        <String>[
          '/',
          '/estabelecimentos',
          '/estabelecimentos/:slug',
          '/estabelecimentos/:slug/categorias/:cat',
          '/estabelecimentos/:slug/produtos/:id',
        ],
      );
    });

    test('folha casa e traz os params de todos os níveis', () {
      final WeaveRouteMatch? m =
          build().match('/estabelecimentos/pizzaria-do-ze/produtos/42');
      expect(m?.route.name, 'produto');
      expect(m?.params['slug'], 'pizzaria-do-ze');
      expect(m?.params['id'], '42');
    });

    test('query convive com a hierarquia', () {
      final WeaveRouteMatch? m = build()
          .match('/estabelecimentos/ze/categorias/bebidas?ordenar=preco');
      expect(m?.params['cat'], 'bebidas');
      expect(m?.params['ordenar'], 'preco');
    });

    test('ancestrais dão breadcrumb sem cirurgia de string', () {
      final WeaveRouteMatch m =
          build().match('/estabelecimentos/ze/produtos/42')!;
      expect(
        m.ancestors.map((WeaveRoute r) => r.name),
        <String>['lojas', 'loja'],
      );
    });

    test('pathFor por nome ainda encontra a rota aninhada', () {
      expect(build().routeByName('produto')?.path,
          '/estabelecimentos/:slug/produtos/:id');
    });
  });

  // ── concursos: /cadernos/:id/gabarito ─────────────────────────────────
  group('concursos · módulo dono de uma subárvore', () {
    test('módulo declara a árvore e o router a consome', () {
      final WeaveModule cadernos = WeaveModule(
        name: 'cadernos',
        routes: <WeaveRoute>[
          WeaveRoute(
            path: '/cadernos',
            builder: (_, _) => _txt('cadernos'),
            children: <WeaveRoute>[
              WeaveRoute(
                path: '/:id',
                builder: (_, _) => _txt('questao'),
                children: <WeaveRoute>[
                  WeaveRoute(
                    path: '/gabarito',
                    name: 'gabarito',
                    builder: (_, _) => _txt('gabarito'),
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final WeaveRouter router = WeaveRouter(routes: cadernos.allRoutes);
      final WeaveRouteMatch? m = router.match('/cadernos/7/gabarito');

      expect(m?.route.name, 'gabarito');
      expect(m?.params['id'], '7');
    });

    test('guard do topo protege a subárvore inteira, uma vez só', () async {
      final _CountingGuard guard = _CountingGuard();
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          WeaveRoute(
            path: '/cadernos',
            guards: <WeaveGuard>[guard],
            builder: (_, _) => _txt('cadernos'),
            children: <WeaveRoute>[
              WeaveRoute(
                path: '/:id',
                builder: (_, _) => _txt('questao'),
                children: <WeaveRoute>[
                  WeaveRoute(path: '/gabarito', builder: (_, _) => _txt('g')),
                ],
              ),
            ],
          ),
        ],
      );

      final WeaveRoute leaf = router.match('/cadernos/7/gabarito')!.route;
      expect(
        leaf.guards,
        hasLength(1),
        reason: 'o guard do avô não pode ser somado duas vezes no neto',
      );
      expect(identical(leaf.guards.single, guard), isTrue);
    });

    test('guard próprio do filho soma ao herdado', () {
      final _CountingGuard raiz = _CountingGuard();
      final _CountingGuard folha = _CountingGuard();
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          WeaveRoute(
            path: '/cadernos',
            guards: <WeaveGuard>[raiz],
            builder: (_, _) => _txt('c'),
            children: <WeaveRoute>[
              WeaveRoute(
                path: '/:id/gabarito',
                guards: <WeaveGuard>[folha],
                builder: (_, _) => _txt('g'),
              ),
            ],
          ),
        ],
      );
      expect(router.match('/cadernos/7/gabarito')!.route.guards, hasLength(2));
    });
  });

  // ── layout persistente por seção ──────────────────────────────────────
  group('layoutBuilder envolve a subárvore', () {
    testWidgets('o shell da loja fica visível na página do produto', (
      WidgetTester t,
    ) async {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          WeaveRoute(
            path: '/lojas/:slug',
            layoutBuilder: (BuildContext c, Widget child) => Column(
              children: <Widget>[const Text('CABEÇALHO DA LOJA'), Expanded(child: child)],
            ),
            builder: (_, _) => _txt('home da loja'),
            children: <WeaveRoute>[
              WeaveRoute(
                path: '/produtos/:id',
                builder: (_, WeaveParams p) => _txt('produto ${p.getString('id')}'),
              ),
            ],
          ),
        ],
      );

      await t.pumpWidget(
        MaterialApp(
          onGenerateRoute: router.routeFactory,
          onGenerateInitialRoutes: router.onGenerateInitialRoutes,
          initialRoute: '/lojas/ze/produtos/42',
        ),
      );
      await t.pumpAndSettle();

      expect(find.text('CABEÇALHO DA LOJA'), findsOneWidget);
      expect(find.text('produto 42'), findsOneWidget);
    });

    testWidgets('layouts aninhados envolvem do mais externo para o interno', (
      WidgetTester t,
    ) async {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          WeaveRoute(
            path: '/a',
            layoutBuilder: (_, Widget child) =>
                Column(children: <Widget>[const Text('EXTERNO'), Expanded(child: child)]),
            builder: (_, _) => _txt('a'),
            children: <WeaveRoute>[
              WeaveRoute(
                path: '/b',
                layoutBuilder: (_, Widget child) => Column(
                  children: <Widget>[const Text('INTERNO'), Expanded(child: child)],
                ),
                builder: (_, _) => _txt('folha'),
              ),
            ],
          ),
        ],
      );

      await t.pumpWidget(
        MaterialApp(
          onGenerateRoute: router.routeFactory,
          onGenerateInitialRoutes: router.onGenerateInitialRoutes,
          initialRoute: '/a/b',
        ),
      );
      await t.pumpAndSettle();

      expect(find.text('EXTERNO'), findsOneWidget);
      expect(find.text('INTERNO'), findsOneWidget);
      expect(find.text('folha'), findsOneWidget);
    });
  });

  // ── deep link: o voltar precisa subir a árvore ────────────────────────
  group('stackAncestorsOnDeepLink', () {
    WeaveRouter build({required bool stack}) => WeaveRouter(
          stackAncestorsOnDeepLink: stack,
          routes: <WeaveRoute>[
            WeaveRoute(
              path: '/cadernos',
              builder: (_, _) => _txt('cadernos'),
              children: <WeaveRoute>[
                WeaveRoute(
                  path: '/:id',
                  builder: (_, WeaveParams p) => _txt('questao ${p.getString('id')}'),
                  children: <WeaveRoute>[
                    WeaveRoute(path: '/gabarito', builder: (_, _) => _txt('gabarito')),
                  ],
                ),
              ],
            ),
          ],
        );

    test('desligado: uma rota só, o voltar sai do app', () {
      expect(build(stack: false).onGenerateInitialRoutes('/cadernos/7/gabarito'),
          hasLength(1));
    });

    test('ligado: empilha /cadernos → /cadernos/7 → /cadernos/7/gabarito', () {
      final List<Route<dynamic>> stack =
          build(stack: true).onGenerateInitialRoutes('/cadernos/7/gabarito');
      expect(
        stack.map((Route<dynamic> r) => r.settings.name),
        <String>['/cadernos', '/cadernos/7', '/cadernos/7/gabarito'],
      );
    });

    testWidgets('o voltar sobe um nível em vez de fechar', (
      WidgetTester t,
    ) async {
      final WeaveRouter router = build(stack: true);
      await t.pumpWidget(
        MaterialApp(
          onGenerateRoute: router.routeFactory,
          onGenerateInitialRoutes: router.onGenerateInitialRoutes,
          initialRoute: '/cadernos/7/gabarito',
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('gabarito'), findsOneWidget);

      t.state<NavigatorState>(find.byType(Navigator)).pop();
      await t.pumpAndSettle();
      expect(find.text('questao 7'), findsOneWidget);

      t.state<NavigatorState>(find.byType(Navigator)).pop();
      await t.pumpAndSettle();
      expect(find.text('cadernos'), findsOneWidget);
    });

    test('query fica só na folha', () {
      final List<Route<dynamic>> stack = build(stack: true)
          .onGenerateInitialRoutes('/cadernos/7/gabarito?destaque=3');
      expect(stack.last.settings.name, '/cadernos/7/gabarito?destaque=3');
      expect(stack.first.settings.name, '/cadernos');
    });

    test('path desconhecido continua caindo no tratamento de 404', () {
      expect(
        build(stack: true).onGenerateInitialRoutes('/nao-existe'),
        hasLength(1),
      );
    });
  });

  group('compatibilidade com declaração plana', () {
    test('sem children, flatRoutes preserva a identidade das rotas', () {
      final WeaveRoute a = WeaveRoute(path: '/a', builder: (_, _) => _txt('a'));
      final WeaveRoute b = WeaveRoute(path: '/b', builder: (_, _) => _txt('b'));
      final WeaveRouter router = WeaveRouter(routes: <WeaveRoute>[a, b]);

      expect(identical(router.flatRoutes[0], a), isTrue);
      expect(identical(router.flatRoutes[1], b), isTrue);
      expect(router.match('/a')!.ancestors, isEmpty);
    });

    test('filho pode declarar path sem barra inicial', () {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          WeaveRoute(
            path: '/loja',
            builder: (_, _) => _txt('l'),
            children: <WeaveRoute>[
              WeaveRoute(path: 'produtos/:id', builder: (_, _) => _txt('p')),
            ],
          ),
        ],
      );
      expect(router.match('/loja/produtos/9')?.params['id'], '9');
    });

    test('when no pai desabilita o ramo inteiro no match do pai', () {
      final WeaveRouter router = WeaveRouter(
        routes: <WeaveRoute>[
          WeaveRoute(
            path: '/beta',
            when: () => false,
            builder: (_, _) => _txt('b'),
            children: <WeaveRoute>[
              WeaveRoute(path: '/x', builder: (_, _) => _txt('x')),
            ],
          ),
        ],
      );
      expect(router.match('/beta'), isNull);
    });
  });
}
