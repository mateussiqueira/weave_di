// Features da 3.0.0: bindings nomeados, erros tipados, eager singleton,
// dispose por binding, validate() e describe().

import 'package:flutter_test/flutter_test.dart';
import 'package:weave_di/weave_di.dart';

class _Svc {
  _Svc(this.tag);
  final String tag;
}

class _Dep {}

class _Closable {
  bool closed = false;
  void close() => closed = true;
}

void main() {
  tearDown(() {
    WeaveLog.reset();
    WeaveContainerAdapter.global.reset();
  });

  // ───────────────────────────────────────────────────────────────────────
  group('bindings nomeados', () {
    test('duas implementações do mesmo tipo convivem', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'n');
      c.bindSingleton<_Svc>(() => _Svc('publico'), name: 'public');
      c.bindSingleton<_Svc>(() => _Svc('autenticado'), name: 'authed');

      expect(c.get<_Svc>(name: 'public').tag, 'publico');
      expect(c.get<_Svc>(name: 'authed').tag, 'autenticado');
    });

    test('nome não é curinga: sem nome não acha o nomeado', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'n2');
      c.bindSingleton<_Svc>(() => _Svc('x'), name: 'a');
      expect(c.tryGet<_Svc>(), isNull);
      expect(c.tryGet<_Svc>(name: 'a'), isNotNull);
    });

    test('sem nome e com nome são registros independentes', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'n3');
      c.bindSingleton<_Svc>(() => _Svc('anonimo'));
      c.bindSingleton<_Svc>(() => _Svc('nomeado'), name: 'x');
      expect(c.get<_Svc>().tag, 'anonimo');
      expect(c.get<_Svc>(name: 'x').tag, 'nomeado');
    });

    test('o nome pode ser um enum, não só String', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'n4');
      c.bindSingleton<_Svc>(() => _Svc('dev'), name: _Env.dev);
      c.bindSingleton<_Svc>(() => _Svc('prod'), name: _Env.prod);
      expect(c.get<_Svc>(name: _Env.prod).tag, 'prod');
    });

    test('unbind e override respeitam o nome', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'n5');
      c.bindSingleton<_Svc>(() => _Svc('a'), name: 'a');
      c.bindSingleton<_Svc>(() => _Svc('b'), name: 'b');

      c.overrideFactory<_Svc>(() => _Svc('mock'), name: 'a');
      expect(c.get<_Svc>(name: 'a').tag, 'mock');
      expect(c.get<_Svc>(name: 'b').tag, 'b');

      c.unbind<_Svc>(name: 'a');
      expect(c.tryGet<_Svc>(name: 'a'), isNull);
      expect(c.tryGet<_Svc>(name: 'b'), isNotNull);
    });

    test('escopo resolve o nomeado do pai', () {
      final WeaveContainerAdapter parent =
          WeaveContainerAdapter.create(name: 'p');
      parent.bindSingleton<_Svc>(() => _Svc('do pai'), name: 'k');
      expect(parent.createScope().get<_Svc>(name: 'k').tag, 'do pai');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('erros tipados', () {
    test('não registrado é WeaveNotRegisteredError, ainda StateError', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'e');
      expect(
        () => c.get<_Svc>(),
        throwsA(
          isA<WeaveNotRegisteredError>()
              .having((WeaveNotRegisteredError e) => e.type, 'type', _Svc)
              .having((WeaveNotRegisteredError e) => e, 'é StateError',
                  isA<StateError>()),
        ),
      );
    });

    test('a mensagem diz onde procurou e o que existe', () {
      final WeaveContainerAdapter parent =
          WeaveContainerAdapter.create(name: 'app');
      parent.bindSingleton<_Dep>(_Dep.new);
      final WeaveContainer scope = parent.createScope();

      try {
        scope.get<_Svc>();
        fail('deveria lançar');
      } on WeaveNotRegisteredError catch (e) {
        expect(e.message, contains('_Svc'));
        expect(e.message, contains('app'));
        expect(e.message, contains('_Dep'), reason: 'lista o que existe');
        expect(e.searchedContainers, contains('app'));
      }
    });

    test('nome aparece na mensagem', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'e2');
      try {
        c.get<_Svc>(name: 'authed');
        fail('deveria lançar');
      } on WeaveNotRegisteredError catch (e) {
        expect(e.message, contains('name: authed'));
        expect(e.name, 'authed');
      }
    });

    test('ciclo é WeaveCircularDependencyError com a cadeia', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'e3');
      c.bindLazy<_Svc>(() => c.get<_Svc>());
      expect(
        () => c.get<_Svc>(),
        throwsA(
          isA<WeaveCircularDependencyError>()
              .having((WeaveCircularDependencyError e) => e.chain, 'chain',
                  hasLength(greaterThanOrEqualTo(2))),
        ),
      );
    });

    test('get sem argumento de tipo é erro explícito', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'e4');
      expect(
        () => c.get<dynamic>(),
        throwsA(isA<WeaveMissingTypeArgumentError>()),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('isRegistered vs canResolve', () {
    test('isRegistered é local; canResolve sobe', () {
      final WeaveContainerAdapter parent =
          WeaveContainerAdapter.create(name: 'p2');
      parent.bindSingleton<_Svc>(() => _Svc('x'));
      final WeaveContainer scope = parent.createScope();

      expect(scope.isRegistered<_Svc>(), isFalse, reason: 'não é daqui');
      expect(scope.canResolve<_Svc>(), isTrue, reason: 'mas resolve');
      expect(scope.get<_Svc>().tag, 'x');
    });

    test('isRegistered enxerga override sem registro base', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'p3');
      c.overrideFactory<_Svc>(() => _Svc('o'));
      expect(c.isRegistered<_Svc>(), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('eager singleton e warmUp', () {
    test('bindEagerSingleton NÃO instancia no bind', () {
      int builds = 0;
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'w');
      c.bindEagerSingleton<_Svc>(() {
        builds++;
        return _Svc('x');
      });
      expect(builds, 0, reason: 'no bind as dependências podem não existir');
    });

    test('warmUp materializa e é idempotente', () {
      int builds = 0;
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'w2');
      c.bindEagerSingleton<_Svc>(() {
        builds++;
        return _Svc('x');
      });

      expect(c.warmUp().isValid, isTrue);
      expect(builds, 1);
      c.warmUp();
      expect(builds, 1, reason: 'idempotente');
    });

    test('warmUp agrega falhas em vez de parar na primeira', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'w3');
      c.bindEagerSingleton<_Svc>(() => throw StateError('falha A'));
      c.bindEagerSingleton<_Dep>(() => throw StateError('falha B'));

      final WeaveValidationReport r = c.warmUp();
      expect(r.isValid, isFalse);
      expect(r.issues, hasLength(2));
      expect(r.issues.every((i) => i.kind == WeaveIssueKind.threw), isTrue);
    });

    test('lazy não é tocado pelo warmUp', () {
      int builds = 0;
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'w4');
      c.bindSingleton<_Svc>(() {
        builds++;
        return _Svc('x');
      });
      c.warmUp();
      expect(builds, 0);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('dispose por binding', () {
    test('unbind avisa o callback', () {
      final _Closable closable = _Closable();
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'd');
      c.bindSingleton<_Closable>(
        () => closable,
        dispose: (_Closable x) => x.close(),
      );
      c.get<_Closable>();

      c.unbind<_Closable>();
      expect(closable.closed, isTrue);
    });

    test('reset avisa', () {
      final _Closable closable = _Closable();
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'd2');
      c.bindSingleton<_Closable>(() => closable,
          dispose: (_Closable x) => x.close());
      c.get<_Closable>();

      c.reset();
      expect(closable.closed, isTrue);
    });

    test('descartar escopo avisa os bindings dele', () {
      final _Closable closable = _Closable();
      final WeaveContainerAdapter root =
          WeaveContainerAdapter.create(name: 'd3');
      final WeaveContainer scope = root.createScope();
      scope.bindSingleton<_Closable>(() => closable,
          dispose: (_Closable x) => x.close());
      scope.get<_Closable>();

      root.disposeScope(scope);
      expect(closable.closed, isTrue);
    });

    test('rebind descarta a instância anterior', () {
      final _Closable primeiro = _Closable();
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'd4');
      c.bindSingleton<_Closable>(() => primeiro,
          dispose: (_Closable x) => x.close());
      c.get<_Closable>();

      c.bindSingleton<_Closable>(_Closable.new);
      expect(primeiro.closed, isTrue);
    });

    test('instância nunca criada não recebe dispose', () {
      bool chamou = false;
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'd5');
      c.bindSingleton<_Closable>(_Closable.new,
          dispose: (_) => chamou = true);
      c.unbind<_Closable>();
      expect(chamou, isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('validate', () {
    test('grafo são passa', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'v');
      c.bindSingleton<_Dep>(_Dep.new);
      c.bindSingleton<_Svc>(() {
        c.get<_Dep>();
        return _Svc('ok');
      });

      final WeaveValidationReport r = c.validate();
      expect(r.isValid, isTrue);
      expect(r.checked, 2);
    });

    test('dependência faltando é reportada, não lançada', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'v2');
      c.bindSingleton<_Svc>(() {
        c.get<_Dep>();
        return _Svc('x');
      });

      final WeaveValidationReport r = c.validate();
      expect(r.isValid, isFalse);
      expect(r.issues.single.kind, WeaveIssueKind.missing);
      expect(r.issues.single.type, _Svc);
    });

    test('ciclo é reportado', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'v3');
      c.bindSingleton<_Svc>(() => c.get<_Svc>());
      expect(c.validate().issues.single.kind, WeaveIssueKind.cycle);
    });

    test('não deixa rastro: o que não existia é descartado', () {
      int builds = 0;
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'v4');
      c.bindSingleton<_Svc>(() {
        builds++;
        return _Svc('x');
      });

      c.validate();
      expect(builds, 1);
      c.get<_Svc>();
      expect(builds, 2, reason: 'a instância do validate foi descartada');
    });

    test('preserva instância que já existia antes', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'v5');
      c.bindSingleton<_Svc>(() => _Svc('x'));
      final _Svc antes = c.get<_Svc>();
      c.validate();
      expect(identical(c.get<_Svc>(), antes), isTrue);
    });

    test('factory com argumento é pulada', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'v6');
      c.bindFactory<_Svc, String>((String s) => _Svc(s));
      expect(c.validate().checked, 0);
    });

    test('throwIfInvalid lança com o relatório', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'v7');
      c.bindSingleton<_Svc>(() => throw StateError('boom'));
      expect(() => c.validate().throwIfInvalid(), throwsStateError);
    });
  });

  group('describe', () {
    test('lista chaves, lifetime e estado', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'ds');
      c.bindSingleton<_Svc>(() => _Svc('x'), name: 'a');
      c.bind<_Dep>(_Dep.new);
      c.get<_Svc>(name: 'a');

      final String out = c.describe();
      expect(out, contains('ds'));
      expect(out, contains('_Svc(name: a)'));
      expect(out, contains('instanciado'));
      expect(out, contains('transient'));
    });

    test('lineage mostra a cadeia de containers', () {
      final WeaveContainerAdapter root =
          WeaveContainerAdapter.create(name: 'raiz');
      final WeaveContainerAdapter scope = root.createScopeNamed('filho');
      expect(scope.lineage, <String>['raiz.filho', 'raiz']);
    });
  });
}

enum _Env { dev, prod }
