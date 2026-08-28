// Regressões da auditoria adversarial da 3.0.0.
// Cada teste corresponde a um defeito REPRODUZIDO antes de ser corrigido.

import 'package:flutter_test/flutter_test.dart';
import 'package:weave_di/weave_di.dart';

class _Res {
  _Res(this.id);
  final int id;
  int closes = 0;
  void close() => closes++;
}

class _Explosive {
  void close() => throw StateError('boom no teardown');
}

class _Dep {
  _Dep(this.tag);
  final String tag;
}

void main() {
  tearDown(() {
    WeaveLog.reset();
    WeaveContainerAdapter.global.reset();
  });

  // ───────────────────────────────────────────────────────────────────────
  group('B1 · callback de dispose que lança não trava o container', () {
    test('os irmãos ainda são descartados', () {
      final List<_Res> recursos =
          List<_Res>.generate(5, (int i) => _Res(i));
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'b1');

      for (int i = 0; i < 5; i++) {
        if (i == 2) {
          c.bindSingleton<_Explosive>(
            _Explosive.new,
            dispose: (_Explosive x) => x.close(),
          );
        } else {
          c.bindSingleton<_Res>(
            () => recursos[i],
            name: 'r$i',
            dispose: (_Res x) => x.close(),
          );
        }
      }
      for (int i = 0; i < 5; i++) {
        if (i != 2) c.get<_Res>(name: 'r$i');
      }
      c.get<_Explosive>();

      expect(c.reset, returnsNormally);
      for (final int i in <int>[0, 1, 3, 4]) {
        expect(recursos[i].closes, 1, reason: 'recurso $i deveria fechar');
      }
    });

    test('o container fica limpo depois da exceção', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'b1b');
      c.bindSingleton<_Explosive>(_Explosive.new,
          dispose: (_Explosive x) => x.close());
      c.get<_Explosive>();

      c.reset();
      expect(c.registeredKeys, isEmpty);
      expect(c.reset, returnsNormally, reason: 'não relança para sempre');
    });

    test('escopo é desmontado mesmo se o onDispose lançar', () {
      final WeaveContainerAdapter root =
          WeaveContainerAdapter.create(name: 'b1c');
      final WeaveContainer scope =
          root.createScope(onDispose: () => throw StateError('boom'));
      scope.bindSingleton<_Dep>(() => _Dep('x'));
      scope.get<_Dep>();

      expect(() => root.disposeScope(scope), returnsNormally);
      expect(
        scope.tryGet<_Dep>(),
        isNull,
        reason: 'escopo meio-descartado que ainda resolve é pior que o erro',
      );
    });

    test('disposeScope que lança não deixa o escopo listado no pai', () {
      final WeaveContainerAdapter root =
          WeaveContainerAdapter.create(name: 'b1d');
      final WeaveContainerAdapter scope = root.createScopeNamed('zumbi');
      scope.bindSingleton<_Explosive>(_Explosive.new,
          dispose: (_Explosive x) => x.close());
      scope.get<_Explosive>();

      root.disposeScope(scope);
      expect(root.describe(), isNot(contains('zumbi')));
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('B2 · resetSingletons não reentrega instância doada', () {
    test('bindInstance descartado não volta como cadáver', () {
      final _Res recurso = _Res(1);
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'b2');
      c.bindInstance<_Res>(recurso);
      expect(identical(c.get<_Res>(), recurso), isTrue);

      c.resetSingletons();
      expect(
        c.tryGet<_Res>(),
        isNull,
        reason: 'o container não sabe reconstruir um objeto que recebeu pronto',
      );
    });

    test('lazy continua reconstruindo normalmente', () {
      int builds = 0;
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'b2b');
      c.bindSingleton<_Dep>(() {
        builds++;
        return _Dep('x');
      });
      c.get<_Dep>();
      c.resetSingletons();
      c.get<_Dep>();
      expect(builds, 2);
    });

    test('dispose de instância doada roda uma vez só', () {
      final _Res recurso = _Res(1);
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'b2c');
      c.bindInstance<_Res>(recurso);
      c.get<_Res>();

      c.resetSingletons();
      c.resetSingletons();
      expect(recurso.closes, 0, reason: 'bindInstance não recebe dispose');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('I1 · validate não deixa rastro', () {
    test('dependência transitiva é descartada', () {
      final List<String> criados = <String>[];
      final List<String> descartados = <String>[];
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'i1');

      c.bindSingleton<_Dep>(
        () {
          criados.add('dep');
          return _Dep('dep');
        },
        dispose: (_) => descartados.add('dep'),
      );
      c.bindSingleton<_Res>(
        () {
          c.get<_Dep>();
          criados.add('root');
          return _Res(1);
        },
        dispose: (_) => descartados.add('root'),
      );

      c.validate();
      expect(
        descartados..sort(),
        <String>['dep', 'root'],
        reason: 'a dependência puxada por tabela também tem que sair',
      );
    });

    test('validate repetido não acumula instâncias', () {
      int builds = 0;
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'i1b');
      c.bindSingleton<_Dep>(() {
        builds++;
        return _Dep('x');
      });

      c.validate();
      c.validate();
      c.validate();
      expect(builds, 3, reason: 'cada validate recria e descarta');
    });

    test('instância que já existia é preservada', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'i1c');
      c.bindSingleton<_Dep>(() => _Dep('x'));
      final _Dep antes = c.get<_Dep>();
      c.validate();
      expect(identical(c.get<_Dep>(), antes), isTrue);
    });
  });

  group('I2 · validate e warmUp respeitam overrides', () {
    test('override quebrado sobre registro bom é reprovado', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'i2');
      c.bindSingleton<_Dep>(() => _Dep('bom'));
      c.overrideFactory<_Dep>(() => throw StateError('fake quebrado'));

      expect(
        c.validate().isValid,
        isFalse,
        reason: 'a resolução real usa o override — validar o registro mente',
      );
    });

    test('registro quebrado sob override bom é aprovado', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'i2b');
      c.bindSingleton<_Dep>(() => throw StateError('real quebrado'));
      c.overrideFactory<_Dep>(() => _Dep('fake'));

      expect(c.validate().isValid, isTrue);
    });

    test('warmUp não constrói o eager real por baixo do override', () {
      final List<String> rodou = <String>[];
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'i2c');
      c.bindEagerSingleton<_Dep>(() {
        rodou.add('real');
        return _Dep('real');
      });
      c.overrideFactory<_Dep>(() {
        rodou.add('fake');
        return _Dep('fake');
      });

      c.warmUp();
      expect(rodou, isNot(contains('real')));
    });
  });

  group('M2 · warmUp desce em escopos', () {
    test('eager de um escopo é materializado', () {
      int builds = 0;
      final WeaveContainerAdapter root =
          WeaveContainerAdapter.create(name: 'm2');
      final WeaveContainer scope = root.createScope();
      scope.bindEagerSingleton<_Dep>(() {
        builds++;
        return _Dep('x');
      });

      final WeaveValidationReport r = root.warmUp();
      expect(builds, 1);
      expect(r.checked, 1);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('I3 · ciclo em factory com argumento é erro tipado', () {
    test('get1 detecta ciclo em vez de estourar a pilha', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'i3');
      c.bindFactory<_Dep, String>((String s) => c.get1<_Dep, String>(s));

      expect(
        () => c.get1<_Dep, String>('x'),
        throwsA(isA<WeaveCircularDependencyError>()),
      );
    });

    test('get1 sem argumento de tipo é erro explícito', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'i3b');
      expect(
        () => c.get1<dynamic, String>('x'),
        throwsA(isA<WeaveMissingTypeArgumentError>()),
      );
    });

    test('get1 normal continua funcionando', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'i3c');
      c.bindFactory<_Dep, String>(_Dep.new);
      expect(c.get1<_Dep, String>('ok').tag, 'ok');
      expect(c.get1<_Dep, String>('again').tag, 'again');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('I4 · erro descreve a cadeia a partir de onde foi pedido', () {
    test('escopo aninhado aparece na mensagem, com os vizinhos', () {
      final WeaveContainerAdapter root =
          WeaveContainerAdapter.create(name: 'app');
      root.bindSingleton<_Dep>(() => _Dep('raiz'), name: 'authed');
      final WeaveContainerAdapter auth = root.createScopeNamed('auth');
      auth.bindSingleton<_Res>(() => _Res(1), name: 'primary');
      final WeaveContainerAdapter login = auth.createScopeNamed('login');

      try {
        login.get<_Res>(name: 'primaryy'); // typo de propósito
        fail('deveria lançar');
      } on WeaveNotRegisteredError catch (e) {
        expect(
          e.searchedContainers,
          <String>['app.auth.login', 'app.auth', 'app'],
          reason: 'a cadeia inteira, não só a raiz',
        );
        expect(
          e.message,
          contains('primary'),
          reason: 'o binding quase-certo tem que aparecer',
        );
      }
    });
  });

  group('M1 · nome numérico é rejeitado em debug', () {
    test('1 e 1.0 colidiriam — o assert impede', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'm1');
      expect(
        () => c.bindSingleton<_Dep>(() => _Dep('a'), name: 1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('String e enum seguem válidos', () {
      final WeaveContainerAdapter c = WeaveContainerAdapter.create(name: 'm1b');
      expect(
        () {
          c.bindSingleton<_Dep>(() => _Dep('a'), name: 'a');
          c.bindSingleton<_Dep>(() => _Dep('b'), name: _N.b);
        },
        returnsNormally,
      );
    });
  });
}

enum _N { b }
