import 'container.dart';
import 'container_adapter.dart';

/// Unidade de organização do DI.
///
/// Agrupa um ou mais registros que podem ser aplicados a um container.
/// Útil pra organizar binds por feature ou módulo.
@Deprecated(
  'Use WeaveModule, que tem container próprio, lifecycle, ordem topológica '
  'e install idempotente. WeaveBinding não é consumido por nenhuma outra '
  'parte do package. Será removido na 3.0.0.',
)
class WeaveBinding {
  /// Nome para debugging.
  final String name;

  /// Função que registra as dependências no container.
  final void Function(WeaveContainer container) register;

  /// Bindings que devem ser registrados antes deste.
  final List<WeaveBinding> imports;

  const WeaveBinding({
    required this.name,
    required this.register,
    this.imports = const [],
  });

  /// Aplica este binding no container global.
  void apply() {
    for (final dep in imports) {
      dep.apply();
    }
    register(WeaveContainerAdapter.global);
  }

  /// Aplica este binding em um container específico.
  void applyTo(WeaveContainer container) {
    for (final dep in imports) {
      dep.applyTo(container);
    }
    register(container);
  }

  /// Cria uma instância de binding com factory sem parâmetros.
  static WeaveBinding create<T>({
    required String name,
    required WeaveFactory<T> factory,
    bool singleton = false,
    List<WeaveBinding> imports = const [],
  }) {
    return WeaveBinding(
      name: name,
      register: (c) {
        if (singleton) {
          c.bindSingleton<T>(factory);
        } else {
          c.bind<T>(factory);
        }
      },
      imports: imports,
    );
  }

  /// Cria uma instância de binding com factory com 1 parâmetro.
  static WeaveBinding create1<T, A>({
    required String name,
    required WeaveFactory1<T, A> factory,
    List<WeaveBinding> imports = const [],
  }) {
    return WeaveBinding(
      name: name,
      register: (c) => c.bindFactory<T, A>(factory),
      imports: imports,
    );
  }

  /// Cria uma instância de binding com factory com 2 parâmetros.
  static WeaveBinding create2<T, A, B>({
    required String name,
    required WeaveFactory2<T, A, B> factory,
    List<WeaveBinding> imports = const [],
  }) {
    return WeaveBinding(
      name: name,
      register: (c) => c.bindFactory2<T, A, B>(factory),
      imports: imports,
    );
  }

  /// Cria uma instância de binding com factory com 3 parâmetros.
  static WeaveBinding create3<T, A, B, C>({
    required String name,
    required WeaveFactory3<T, A, B, C> factory,
    List<WeaveBinding> imports = const [],
  }) {
    return WeaveBinding(
      name: name,
      register: (c) => c.bindFactory3<T, A, B, C>(factory),
      imports: imports,
    );
  }

  @override
  String toString() => 'WeaveBinding($name)';
}
