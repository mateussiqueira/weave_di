// `builder` deixa de ser obrigatório quando a rota usa `injectFactory`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave_di/weave_di.dart';

class _Svc {
  _Svc(this.tag);
  final String tag;
}

void main() {
  tearDown(WeaveContainerAdapter.global.reset);

  test('rota com injectFactory dispensa o builder', () {
    expect(
      () => WeaveRoute(
        path: '/x',
        injectFactory: (_, _, _) => const SizedBox(),
      ),
      returnsNormally,
    );
  });

  test('rota sem builder e sem injectFactory é erro em debug', () {
    expect(
      () => WeaveRoute(path: '/x'),
      throwsA(isA<AssertionError>()),
    );
  });

  test('builder continua funcionando como antes', () {
    final WeaveRoute r = WeaveRoute(
      path: '/x',
      builder: (_, _) => const SizedBox(),
    );
    expect(r.builder, isNotNull);
  });

  testWidgets('injectFactory recebe o container do router', (
    WidgetTester t,
  ) async {
    WeaveContainerAdapter.global.bindSingleton<_Svc>(() => _Svc('do container'));

    final WeaveRouter router = WeaveRouter(
      routes: <WeaveRoute>[
        WeaveRoute(
          path: '/',
          injectFactory: (_, _, WeaveContainer c) =>
              Scaffold(body: Text(c.get<_Svc>().tag)),
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

    expect(find.text('do container'), findsOneWidget);
  });

  testWidgets('injectFactory tem precedência sobre builder', (
    WidgetTester t,
  ) async {
    final WeaveRouter router = WeaveRouter(
      routes: <WeaveRoute>[
        WeaveRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('BUILDER')),
          injectFactory: (_, _, _) =>
              const Scaffold(body: Text('INJECT')),
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

    expect(find.text('INJECT'), findsOneWidget);
    expect(find.text('BUILDER'), findsNothing);
  });
}
