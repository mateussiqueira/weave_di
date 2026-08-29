// onInit/onDispose por construtor: lifecycle sem exigir subclasse.

import 'package:flutter_test/flutter_test.dart';
import 'package:weave_di/weave_di.dart';

class Svc {
  bool carregado = false;
  Future<void> carregar() async => carregado = true;
}

class _Subclasse extends WeaveModule {
  _Subclasse() : super(name: 'sub');
  int inits = 0;
  @override
  Future<void> onInit() async => inits++;
}

void main() {
  tearDown(WeaveContainerAdapter.global.reset);

  test('onInit do construtor roda com o container do módulo', () async {
    final WeaveModule m = WeaveModule(
      name: 'auth',
      binds: <WeaveBind>[(WeaveContainer c) => c.bindSingleton<Svc>(Svc.new)],
      onInit: (WeaveContainer c) => c.get<Svc>().carregar(),
    );

    await (WeaveModuleRegistry()..register(m)).installAll();
    expect(m.container.get<Svc>().carregado, isTrue);
  });

  test('onInit roda DEPOIS dos binds, não durante', () async {
    final List<String> ordem = <String>[];
    final WeaveModule m = WeaveModule(
      name: 'ordem',
      binds: <WeaveBind>[
        (WeaveContainer c) {
          ordem.add('bind');
          c.bindSingleton<Svc>(Svc.new);
        },
      ],
      onInit: (WeaveContainer c) async => ordem.add('init'),
    );

    await (WeaveModuleRegistry()..register(m)).installAll();
    expect(ordem, <String>['bind', 'init']);
  });

  test('onInit roda uma vez só, mesmo com installAll repetido', () async {
    int inits = 0;
    final WeaveModule m = WeaveModule(
      name: 'once',
      onInit: (WeaveContainer c) async => inits++,
    );
    final WeaveModuleRegistry r = WeaveModuleRegistry()..register(m);

    await r.installAll();
    await r.installAll();
    expect(inits, 1);
  });

  test('import é inicializado antes de quem importa', () async {
    final List<String> ordem = <String>[];
    final WeaveModule base = WeaveModule(
      name: 'base',
      onInit: (WeaveContainer c) async => ordem.add('base'),
    );
    final WeaveModule topo = WeaveModule(
      name: 'topo',
      imports: <WeaveModule>[base],
      onInit: (WeaveContainer c) async => ordem.add('topo'),
    );

    await (WeaveModuleRegistry()..register(topo)).installAll();
    expect(ordem, <String>['base', 'topo']);
  });

  test('onDispose do construtor roda no disposeAll', () async {
    final List<String> ordem = <String>[];
    final WeaveModule m = WeaveModule(
      name: 'd',
      onInit: (WeaveContainer c) async => ordem.add('init'),
      onDispose: (WeaveContainer c) async => ordem.add('dispose'),
    );
    final WeaveModuleRegistry r = WeaveModuleRegistry()..register(m);

    await r.installAll();
    await r.disposeAll();
    expect(ordem, <String>['init', 'dispose']);
  });

  test('subclasse que sobrescreve continua funcionando', () async {
    final _Subclasse m = _Subclasse();
    await (WeaveModuleRegistry()..register(m)).installAll();
    expect(m.inits, 1);
  });

  test('módulo sem callback nem sobrescrita não quebra', () async {
    final WeaveModule m = WeaveModule(name: 'vazio');
    await expectLater(
      (WeaveModuleRegistry()..register(m)).installAll(),
      completes,
    );
  });
}
