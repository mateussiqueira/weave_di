// Exports de módulo: o que torna WeaveModule utilizável num app com vários
// módulos que compartilham infraestrutura.

import 'package:flutter_test/flutter_test.dart';
import 'package:weave_di/weave_di.dart';

class Http {
  Http(this.id);
  final int id;
}

class Secret {}

class Feature {
  Feature(this.http);
  final Http http;
}

void main() {
  tearDown(WeaveContainerAdapter.global.reset);

  test('sem export, o bind do módulo continua invisível', () {
    final WeaveModule auth = WeaveModule(
      name: 'auth-priv',
      binds: <WeaveBind>[(WeaveContainer c) => c.bindSingleton<Secret>(Secret.new)],
    );
    auth.install();
    expect(WeaveContainerAdapter.global.canResolve<Secret>(), isFalse);
  });

  test('com export, outro módulo resolve pelo pai', () {
    final WeaveModule auth = WeaveModule(
      name: 'auth',
      binds: <WeaveBind>[(WeaveContainer c) => c.bindSingleton<Http>(() => Http(1))],
      exports: <WeaveExport<Object?>>[const WeaveExport<Http>()],
    );
    final WeaveModule billing = WeaveModule(
      name: 'billing',
      imports: <WeaveModule>[auth],
      binds: <WeaveBind>[
        (WeaveContainer c) => c.bindSingleton<Feature>(() => Feature(c.get<Http>())),
      ],
    );
    billing.install();

    expect(billing.container.get<Feature>().http.id, 1);
  });

  test('o singleton é o MESMO dos dois lados', () {
    final WeaveModule auth = WeaveModule(
      name: 'auth2',
      binds: <WeaveBind>[(WeaveContainer c) => c.bindSingleton<Http>(() => Http(2))],
      exports: <WeaveExport<Object?>>[const WeaveExport<Http>()],
    );
    auth.install();

    expect(
      identical(auth.container.get<Http>(), WeaveContainerAdapter.global.get<Http>()),
      isTrue,
      reason: 'encaminhar não pode criar uma segunda instância',
    );
  });

  test('transient exportado continua transient', () {
    int builds = 0;
    final WeaveModule m = WeaveModule(
      name: 'tr',
      binds: <WeaveBind>[
        (WeaveContainer c) => c.bind<Http>(() {
              builds++;
              return Http(builds);
            }),
      ],
      exports: <WeaveExport<Object?>>[const WeaveExport<Http>()],
    );
    m.install();

    WeaveContainerAdapter.global.get<Http>();
    WeaveContainerAdapter.global.get<Http>();
    expect(builds, 2, reason: 'encaminhar como singleton mudaria o lifetime');
  });

  test('export nomeado preserva o nome', () {
    final WeaveModule m = WeaveModule(
      name: 'nm',
      binds: <WeaveBind>[
        (WeaveContainer c) => c.bindSingleton<Http>(() => Http(9), name: 'api'),
      ],
      exports: <WeaveExport<Object?>>[const WeaveExport<Http>(name: 'api')],
    );
    m.install();

    expect(WeaveContainerAdapter.global.get<Http>(name: 'api').id, 9);
    expect(WeaveContainerAdapter.global.tryGet<Http>(), isNull);
  });

  test('descartar o módulo retira o encaminhamento do pai', () {
    final WeaveModule m = WeaveModule(
      name: 'dsp',
      binds: <WeaveBind>[(WeaveContainer c) => c.bindSingleton<Http>(() => Http(3))],
      exports: <WeaveExport<Object?>>[const WeaveExport<Http>()],
    );
    m.install();
    expect(WeaveContainerAdapter.global.canResolve<Http>(), isTrue);

    m.disposeContainer();
    expect(
      WeaveContainerAdapter.global.canResolve<Http>(),
      isFalse,
      reason: 'binding apontando para escopo morto é pior que ausência',
    );
  });

  test('registry instala o grafo com exports na ordem certa', () async {
    final WeaveModule auth = WeaveModule(
      name: 'a',
      binds: <WeaveBind>[(WeaveContainer c) => c.bindSingleton<Http>(() => Http(7))],
      exports: <WeaveExport<Object?>>[const WeaveExport<Http>()],
    );
    final WeaveModule feat = WeaveModule(
      name: 'f',
      imports: <WeaveModule>[auth],
      binds: <WeaveBind>[
        (WeaveContainer c) => c.bindSingleton<Feature>(() => Feature(c.get<Http>())),
      ],
    );

    await (WeaveModuleRegistry()..register(feat)).installAll();
    expect(feat.container.get<Feature>().http.id, 7);
  });
}
