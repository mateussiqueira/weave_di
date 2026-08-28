import 'container.dart';
import 'container_adapter.dart';
import 'route.dart';

/// Função para registrar dependências em um container.
typedef WeaveBind<T extends Object> = void Function(WeaveContainer container);

/// Módulo pra organizar DI e rotas por feature.
///
/// Um módulo agrupa binds e rotas relacionados. Pode ser
/// usado direto ou estendido com lifecycle.
///
/// ```dart
/// // Uso direto
/// final authModule = WeaveModule(
///   name: 'auth',
///   binds: [(c) => c.bindSingleton<AuthService>(() => AuthServiceImpl())],
///   routes: [WeaveRoute(path: '/login', builder: ...)],
/// );
/// authModule.install();
///
/// // Com lifecycle
/// class AuthModule extends WeaveModule {
///   AuthModule() : super(name: 'auth', binds: [...], routes: [...]);
///
///   @override
///   Future<void> onInit() async { /* async setup */ }
///
///   @override
///   Future<void> onDispose() async { /* cleanup */ }
/// }
/// ```
class WeaveModule {
  /// Nome do módulo para identificação.
  final String name;

  /// Lista de binds para registrar no container.
  final List<WeaveBind> binds;

  /// Rotas deste módulo.
  final List<WeaveRoute> routes;

  /// Sub-módulos importados.
  final List<WeaveModule> imports;

  /// Container isolado deste módulo.
  late final WeaveContainer container;

  WeaveModule({
    required this.name,
    this.binds = const [],
    this.routes = const [],
    this.imports = const [],
  }) {
    container = WeaveContainerAdapter.create(name: name);
  }

  /// Lifecycle: chamado após todos os imports serem instalados.
  Future<void> onInit() async {}

  /// Lifecycle: chamado quando o módulo é descartado.
  Future<void> onDispose() async {}

  /// Obtém todas as rotas incluindo rotas de imports.
  List<WeaveRoute> get allRoutes {
    final result = <WeaveRoute>[];
    for (final imp in imports) {
      result.addAll(imp.allRoutes);
    }
    result.addAll(routes);
    return result;
  }

  /// Instala os binds no container isolado do módulo.
  void install() {
    for (final imp in imports) {
      imp.install();
    }
    for (final bind in binds) {
      bind(container);
    }
  }

  /// Instala os binds no container de um módulo específico.
  void installInto(WeaveContainer targetContainer) {
    for (final imp in imports) {
      imp.installInto(targetContainer);
    }
    for (final bind in binds) {
      bind(targetContainer);
    }
  }

  /// Instala os binds no container global.
  void installGlobal() {
    for (final imp in imports) {
      imp.installGlobal();
    }
    for (final bind in binds) {
      bind(WeaveContainerAdapter.global);
    }
  }

  @override
  String toString() => 'WeaveModule($name)';
}

/// Registry centralizado de módulos.
///
/// Gerencia lifecycle e dependências entre módulos.
/// ```dart
/// final registry = WeaveModuleRegistry();
/// registry.register(AuthModule());
/// registry.register(HomeModule(imports: [registry.get<AuthModule>('auth')]));
/// await registry.installAll();
/// await registry.disposeAll();
/// ```
class WeaveModuleRegistry {
  final Map<String, WeaveModule> _modules = {};
  final List<WeaveModule> _order = [];

  /// Registra um módulo.
  void register(WeaveModule module) {
    _modules[module.name] = module;
    _order.add(module);
  }

  /// Obtém um módulo por nome.
  T get<T extends WeaveModule>(String name) {
    final module = _modules[name];
    if (module is T) return module;
    throw StateError('Module "$name" not found or wrong type');
  }

  /// Instala todos os módulos registrados.
  Future<void> installAll() async {
    for (final module in _order) {
      module.install();
      await module.onInit();
    }
  }

  /// Descarta todos os módulos registrados.
  Future<void> disposeAll() async {
    for (final module in _order.reversed) {
      await module.onDispose();
      module.container.reset();
    }
    _modules.clear();
    _order.clear();
  }

  /// Limpa o registry sem descartar módulos.
  void clear() {
    _modules.clear();
    _order.clear();
  }

  /// Retorna todos os módulos registrados.
  List<WeaveModule> get modules => List.unmodifiable(_order);

  /// Retorna todas as rotas de todos os módulos.
  List<WeaveRoute> get allRoutes {
    final result = <WeaveRoute>[];
    for (final module in _order) {
      result.addAll(module.allRoutes);
    }
    return result;
  }
}
