import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave_di/weave_di.dart';

class _TestService {
  final String name;
  _TestService(this.name);
}

void main() {
  group('WeaveContainerAdapter', () {
    late WeaveContainerAdapter container;

    setUp(() {
      container = WeaveContainerAdapter(name: 'test');
    });

    test('bindSingleton creates singleton instance', () {
      container.bindSingleton<_TestService>(() => _TestService('singleton'));

      final a = container.get<_TestService>();
      final b = container.get<_TestService>();

      expect(a.name, 'singleton');
      expect(identical(a, b), isTrue);
    });

    test('bind creates new instance each time', () {
      container.bind<_TestService>(() => _TestService('transient'));

      final a = container.get<_TestService>();
      final b = container.get<_TestService>();

      expect(a.name, 'transient');
      expect(identical(a, b), isFalse);
    });

    test('throws StateError when type not registered', () {
      expect(() => container.get<_TestService>(), throwsStateError);
    });

    test('overrideFactory replaces binding', () {
      container.bindSingleton<_TestService>(() => _TestService('original'));
      container.overrideFactory<_TestService>(() => _TestService('overridden'));

      expect(container.get<_TestService>().name, 'overridden');
    });

    test('resetOverrides keeps original bindings', () {
      container.bindSingleton<_TestService>(() => _TestService('original'));
      container.overrideFactory<_TestService>(() => _TestService('overridden'));
      container.resetOverrides();

      expect(container.get<_TestService>().name, 'original');
    });

    test('resetSingletons creates new instances', () {
      var counter = 0;
      container.bindSingleton<_TestService>(() => _TestService('s${++counter}'));

      final a = container.get<_TestService>();
      container.resetSingletons();
      final b = container.get<_TestService>();

      expect(a.name, 's1');
      expect(b.name, 's2');
    });

    test('override with singleton false creates transient', () {
      container.bindSingleton<_TestService>(() => _TestService('base'));
      container.overrideFactory<_TestService>(
        () => _TestService('override'),
        singleton: false,
      );

      final a = container.get<_TestService>();
      final b = container.get<_TestService>();

      expect(identical(a, b), isFalse);
    });

    test('unbind removes registration', () {
      container.bindSingleton<String>(() => 'test');
      expect(container.isRegistered<String>(), isTrue);

      container.unbind<String>();
      expect(container.isRegistered<String>(), isFalse);
    });

    test('tryGet returns null for unregistered type', () {
      expect(container.tryGet<String>(), isNull);
    });

    test('tryGet returns value for registered type', () {
      container.bindSingleton<String>(() => 'hello');
      expect(container.tryGet<String>(), 'hello');
    });

    test('throws StateError for circular dependency', () {
      container.bindLazy<String>(
        () => 'String depends on int: ${container.get<int>()}',
      );
      container.bindLazy<int>(() => container.get<String>().length);

      expect(() => container.get<String>(), throwsStateError);
    });

    test('reset clears all bindings', () {
      container.bindSingleton<String>(() => 'test');
      container.reset();

      expect(container.isRegistered<String>(), isFalse);
    });

    test('get1 resolves factory with 1 param', () {
      container.bindFactory<String, int>((n) => 'count: $n');
      expect(container.get1<String, int>(5), 'count: 5');
    });

    test('get2 resolves factory with 2 params', () {
      container.bindFactory2<String, int, int>((a, b) => '$a+$b');
      expect(container.get2<String, int, int>(3, 7), '3+7');
    });

    test('get3 resolves factory with 3 params', () {
      container.bindFactory3<String, int, int, int>((a, b, c) => '$a+$b+$c');
      expect(container.get3<String, int, int, int>(1, 2, 3), '1+2+3');
    });
  });

  group('WeaveContainerAdapter Scopes', () {
    late WeaveContainerAdapter container;

    setUp(() {
      container = WeaveContainerAdapter(name: 'test');
    });

    test('scope inherits parent bindings', () {
      container.bindSingleton<int>(() => 42);
      final scope = container.createScope();

      expect(scope.get<int>(), 42);

      container.disposeScope(scope);
    });

    test('scope can override parent binding', () {
      container.bindSingleton<int>(() => 10);
      final scope = container.createScope();
      scope.bindSingleton<int>(() => 20);

      expect(scope.get<int>(), 20);

      container.disposeScope(scope);
    });

    test('scope does not affect parent after dispose', () {
      container.bindSingleton<String>(() => 'parent');
      final scope = container.createScope();
      scope.bindSingleton<String>(() => 'child');

      container.disposeScope(scope);

      expect(container.get<String>(), 'parent');
    });

    test('disposeScope calls onDispose callback from createScope', () {
      var callbackCalled = false;
      final scope = container.createScope(
        onDispose: () => callbackCalled = true,
      );

      container.disposeScope(scope);

      expect(callbackCalled, isTrue);
    });
  });

  group('WeaveParams', () {
    test('getString returns value or fallback', () {
      const params = WeaveParams({'key': 'value'});
      expect(params.getString('key'), 'value');
      expect(params.getString('missing'), '');
      expect(params.getString('missing', fallback: 'default'), 'default');
    });

    test('getInt parses integer', () {
      const params = WeaveParams({'count': '42'});
      expect(params.getInt('count'), 42);
      expect(params.getInt('missing'), 0);
      expect(params.getInt('invalid'), 0);
    });

    test('getDouble parses double', () {
      const params = WeaveParams({'price': '19.99'});
      expect(params.getDouble('price'), 19.99);
      expect(params.getDouble('missing'), 0.0);
    });

    test('getBool parses boolean', () {
      const params = WeaveParams({'yes': 'true', 'one': '1', 'no': 'false'});
      expect(params.getBool('yes'), isTrue);
      expect(params.getBool('one'), isTrue);
      expect(params.getBool('no'), isFalse);
      expect(params.getBool('missing'), isFalse);
    });

    test('getList parses comma-separated', () {
      const params = WeaveParams({'tags': 'a,b,c'});
      expect(params.getList('tags'), ['a', 'b', 'c']);
      expect(params.getList('missing'), isEmpty);
    });

    test('contains checks key existence', () {
      const params = WeaveParams({'key': 'value'});
      expect(params.contains('key'), isTrue);
      expect(params.contains('missing'), isFalse);
    });

    test('operator [] accesses raw map', () {
      const params = WeaveParams({'key': 'value'});
      expect(params['key'], 'value');
      expect(params['missing'], isNull);
    });

    test('equality works', () {
      const a = WeaveParams({'key': 'value'});
      const b = WeaveParams({'key': 'value'});
      const c = WeaveParams({'key': 'other'});

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('merge combines params', () {
      const params = WeaveParams({'a': '1'});
      final merged = params.merge({'b': '2'});
      expect(merged['a'], '1');
      expect(merged['b'], '2');
    });
  });

  group('WeaveRoute', () {
    testWidgets('builder receives context and WeaveParams', (tester) async {
      final route = WeaveRoute(
        path: '/test/:id',
        builder: (context, params) => Text(params['id'] ?? ''),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => route.builder(
              context,
              const WeaveParams({'id': '42'}),
            ),
          ),
        ),
      );

      expect(find.text('42'), findsOneWidget);
    });

    test('matches returns true for exact path', () {
      final route = WeaveRoute(
        path: '/test',
        builder: (ctx, params) => const SizedBox(),
      );
      expect(route.matches('/test'), isTrue);
    });

    test('matches returns false for different path', () {
      final route = WeaveRoute(
        path: '/test',
        builder: (ctx, params) => const SizedBox(),
      );
      expect(route.matches('/other'), isFalse);
    });

    test('matches with path params', () {
      final route = WeaveRoute(
        path: '/user/:id',
        builder: (ctx, params) => const SizedBox(),
      );
      expect(route.matches('/user/42'), isTrue);
      expect(route.matches('/user/abc'), isTrue);
      expect(route.matches('/user/42/profile'), isFalse);
    });

    test('extractParams returns correct values', () {
      final route = WeaveRoute(
        path: '/user/:id/post/:postId',
        builder: (ctx, params) => const SizedBox(),
      );
      final params = route.extractParams('/user/42/post/99');
      expect(params['id'], '42');
      expect(params['postId'], '99');
    });

    test('copyWith creates new route with overrides', () {
      final route = WeaveRoute(
        path: '/old',
        builder: (ctx, params) => const SizedBox(),
      );
      final copy = route.copyWith(path: '/new');
      expect(copy.path, '/new');
      expect(route.path, '/old');
    });

    test('extractQueryParams parses params', () {
      final params = WeaveRoute.extractQueryParams('/search?q=hello&page=2');
      expect(params['q'], 'hello');
      expect(params['page'], '2');
    });

    test('extractQueryParams returns empty for no query', () {
      final params = WeaveRoute.extractQueryParams('/search');
      expect(params, isEmpty);
    });

    test('extractAllParams combines path and query', () {
      final route = WeaveRoute(
        path: '/user/:id',
        builder: (ctx, params) => const SizedBox(),
      );
      final params = route.extractAllParams('/user/42?tab=posts&sort=new');
      expect(params['id'], '42');
      expect(params['tab'], 'posts');
      expect(params['sort'], 'new');
    });

    test('matches ignores query params', () {
      final route = WeaveRoute(
        path: '/search',
        builder: (ctx, params) => const SizedBox(),
      );
      expect(route.matches('/search?q=hello'), isTrue);
    });
  });

  group('WeaveGuard', () {
    testWidgets('custom guard canActivate', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final guard = WeaveGuard.custom(
        canActivate: (ctx, route, params, matchedRoutes) async => true,
      );
      expect(
        await guard.canActivate(
          tester.element(find.byType(SizedBox)),
          '/test',
          const WeaveParams({}),
          [],
        ),
        isTrue,
      );
    });

    testWidgets('deny guard blocks', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final guard = WeaveGuard.deny();
      expect(
        await guard.canActivate(
          tester.element(find.byType(SizedBox)),
          '/test',
          const WeaveParams({}),
          [],
        ),
        isFalse,
      );
    });

    testWidgets('allow guard permits', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final guard = WeaveGuard.allow();
      expect(
        await guard.canActivate(
          tester.element(find.byType(SizedBox)),
          '/test',
          const WeaveParams({}),
          [],
        ),
        isTrue,
      );
    });
  });

  group('WeaveRouter', () {
    test('match finds route by path', () {
      final router = WeaveRouter(
        routes: [
          WeaveRoute(
            path: '/found',
            builder: (ctx, params) => const SizedBox(),
          ),
        ],
      );
      final result = router.match('/found');
      expect(result, isNotNull);
      expect(result!.route.path, '/found');
    });

    test('match returns null for unknown path', () {
      final router = WeaveRouter(routes: []);
      expect(router.match('/unknown'), isNull);
    });

    test('match extracts params', () {
      final router = WeaveRouter(
        routes: [
          WeaveRoute(
            path: '/user/:id',
            builder: (ctx, params) => const SizedBox(),
          ),
        ],
      );
      final result = router.match('/user/7');
      expect(result, isNotNull);
      expect(result!.params['id'], '7');
    });
  });


  group('WeaveModule', () {
    test('install registers binds', () {
      final module = WeaveModule(
        name: 'test',
        binds: [
          (c) => c.bindSingleton<String>(() => 'from-module'),
        ],
      );
      module.install();
      expect(module.container.get<String>(), 'from-module');
    });

    test('allRoutes includes imported routes', () {
      final core = WeaveModule(
        name: 'core',
        routes: [
          WeaveRoute(path: '/core', builder: (ctx, params) => const SizedBox()),
        ],
      );
      final feature = WeaveModule(
        name: 'feature',
        imports: [core],
        routes: [
          WeaveRoute(
            path: '/feature',
            builder: (ctx, params) => const SizedBox(),
          ),
        ],
      );
      final all = feature.allRoutes;
      expect(all, hasLength(2));
      expect(all.any((r) => r.path == '/core'), isTrue);
      expect(all.any((r) => r.path == '/feature'), isTrue);
    });

    test('installInto registers in target container', () {
      final module = WeaveModule(
        name: 'test',
        binds: [(c) => c.bindSingleton<String>(() => 'injected')],
      );
      final target = WeaveContainerAdapter(name: 'target');
      module.installInto(target);
      expect(target.get<String>(), 'injected');
    });
  });


  group('WeaveTransition', () {
    test('material transition is default', () {
      final route = WeaveRoute(
        path: '/',
        builder: (ctx, params) => const SizedBox(),
      );
      expect(route.transition.type, WeaveTransitionType.material);
    });

    test('can create fade transition', () {
      const transition = WeaveTransition.fade;
      expect(transition.type, WeaveTransitionType.fade);
    });

    testWidgets('fade transition builds correctly', (tester) async {
      const transition = WeaveTransition.fade;
      final routeBuilder = transition.buildRoute(const Text('Test'));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => routeBuilder.pageBuilder(
              context,
              const AlwaysStoppedAnimation(1.0),
              const AlwaysStoppedAnimation(0.0),
            ),
          ),
        ),
      );
      expect(find.text('Test'), findsOneWidget);
    });
  });

  group('WeaveRoute with Injection', () {
    late WeaveContainerAdapter container;

    setUp(() {
      container = WeaveContainerAdapter(name: 'inject-test');
    });

    test('injectFactory receives container', () {
      container.bindSingleton<String>(() => 'injected');
      String? receivedValue;
      final route = WeaveRoute(
        path: '/test',
        builder: (ctx, params) => const SizedBox(),
        injectFactory: (context, params, c) {
          receivedValue = c.get<String>();
          return const SizedBox();
        },
      );
      route.injectFactory!(
        // ignore: invalid_use_of_protected_member
        WidgetsBinding.instance.rootElement! as BuildContext,
        const WeaveParams({}),
        container,
      );
      expect(receivedValue, 'injected');
    });
  });

  group('WeaveModuleRegistry', () {
    test('registers and retrieves modules', () {
      final registry = WeaveModuleRegistry();
      final module = WeaveModule(
        name: 'auth',
        binds: [(c) => c.bindSingleton<String>(() => 'auth')],
      );
      registry.register(module);
      expect(registry.modules, contains(module));
      expect(registry.allRoutes, isEmpty);
    });

    test('allRoutes aggregates routes from all modules', () {
      final registry = WeaveModuleRegistry();
      registry.register(WeaveModule(
        name: 'm1',
        routes: [
          WeaveRoute(path: '/a', builder: (ctx, p) => const SizedBox()),
        ],
      ));
      registry.register(WeaveModule(
        name: 'm2',
        routes: [
          WeaveRoute(path: '/b', builder: (ctx, p) => const SizedBox()),
        ],
      ));
      expect(registry.allRoutes, hasLength(2));
    });
  });
}
