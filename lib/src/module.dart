import 'container.dart';
import 'container_adapter.dart';
import 'export.dart';
import 'route.dart';

/// Função para registrar dependências em um container.
typedef WeaveBind<T extends Object> = void Function(WeaveContainer container);

/// Módulo pra organizar DI e rotas por feature.
///
/// Um módulo agrupa binds e rotas relacionados. Pode ser
/// usado direto ou estendido com lifecycle.
///
/// ```dart
/// final authModule = WeaveModule(
///   name: 'auth',
///   binds: [(c) => c.bindSingleton<AuthService>(() => AuthServiceImpl())],
///   routes: [WeaveRoute(path: '/login', builder: ...)],
/// );
/// authModule.install();
/// ```
///
/// O container do módulo é um **escopo do [parent]** (por padrão o global):
/// o que não estiver registrado localmente é resolvido subindo. Até a 2.0.0
/// era um container solto, sem pai, e portanto invisível para todo o resto.
///
/// Para que as rotas do módulo resolvam a partir dele, passe o container ao
/// router:
///
/// ```dart
/// final router = WeaveRouter(
///   routes: module.allRoutes,
///   container: module.container,
/// );
/// ```
class WeaveModule {
  WeaveModule({
    required this.name,
    this.binds = const <WeaveBind>[],
    this.routes = const <WeaveRoute>[],
    this.imports = const <WeaveModule>[],
    this.exports = const <WeaveExport<Object?>>[],
    WeaveContainer? parent,
    // Parâmetro nomeado não pode começar com `_`.
    // ignore: prefer_initializing_formals
  }) : _parent = parent;

  /// Nome do módulo para identificação.
  final String name;

  /// Lista de binds para registrar no container.
  final List<WeaveBind> binds;

  /// Rotas deste módulo.
  final List<WeaveRoute> routes;

  /// Sub-módulos importados. Controla ordem de instalação.
  final List<WeaveModule> imports;

  /// O que este módulo publica para o resto da aplicação.
  ///
  /// Sem isto, um bind do módulo só existe dentro do escopo dele. Ver
  /// [WeaveExport].
  final List<WeaveExport<Object?>> exports;

  final WeaveContainer? _parent;

  bool _installed = false;

  /// Se [install] já rodou. Ver [WeaveModuleRegistry.installAll].
  bool get isInstalled => _installed;

  WeaveContainer? _container;

  /// Container isolado deste módulo, escopo de [_parent].
  ///
  /// Criado sob demanda: um módulo declarado e nunca instalado não deve
  /// registrar escopo nenhum no global. Recriado após [disposeContainer],
  /// porque um escopo descartado perde o pai e reinstalar nele devolveria um
  /// container órfão — que resolve os binds locais e falha em silêncio nos
  /// do pai.
  WeaveContainer get container => _container ??= _createContainer();

  WeaveContainer _createContainer() {
    final WeaveContainer effectiveParent =
        _parent ?? WeaveContainerAdapter.global;
    if (effectiveParent is WeaveContainerAdapter) {
      return effectiveParent.createScopeNamed(name);
    }
    return effectiveParent.createScope();
  }

  /// Lifecycle: chamado após todos os imports serem instalados.
  Future<void> onInit() async {}

  /// Lifecycle: chamado quando o módulo é descartado.
  Future<void> onDispose() async {}

  /// Todas as rotas, incluindo as dos imports, sem duplicar módulo.
  List<WeaveRoute> get allRoutes {
    final List<WeaveRoute> result = <WeaveRoute>[];
    for (final WeaveModule module in _graph()) {
      result.addAll(module.routes);
    }
    return result;
  }

  /// O grafo de módulos em ordem topológica: import antes de quem importa.
  ///
  /// Deduplica por identidade e lança em ciclo.
  List<WeaveModule> _graph() {
    final List<WeaveModule> ordered = <WeaveModule>[];
    final Set<WeaveModule> done = Set<WeaveModule>.identity();
    final List<WeaveModule> path = <WeaveModule>[];

    void visit(WeaveModule module) {
      if (done.contains(module)) return;
      if (path.any((WeaveModule m) => identical(m, module))) {
        final String cycle =
            <String>[...path.map((WeaveModule m) => m.name), module.name]
                .join(' -> ');
        throw StateError('Ciclo de módulos detectado: $cycle');
      }
      path.add(module);
      for (final WeaveModule imported in module.imports) {
        visit(imported);
      }
      path.removeLast();
      done.add(module);
      ordered.add(module);
    }

    visit(this);

    final Map<String, WeaveModule> byName = <String, WeaveModule>{};
    for (final WeaveModule module in ordered) {
      final WeaveModule? clash = byName[module.name];
      if (clash != null && !identical(clash, module)) {
        throw StateError(
          'Dois módulos distintos com o nome "${module.name}" no mesmo grafo.',
        );
      }
      byName[module.name] = module;
    }

    return ordered;
  }

  /// Instala os binds no container do módulo.
  ///
  /// Idempotente: um módulo importado por dois outros é instalado uma vez
  /// só, preservando as instâncias já criadas. Antes, o rebind descartava
  /// silenciosamente o singleton vivo.
  void install() {
    for (final WeaveModule module in _graph()) {
      module._installSelf();
    }
  }

  /// Instala este módulo se ainda não estiver. Devolve `true` se instalou
  /// agora — é o que impede `onInit` de rodar duas vezes.
  bool _installSelf() {
    if (_installed) return false;
    _installed = true;
    for (final WeaveBind bind in binds) {
      bind(container);
    }
    final WeaveContainer target = _parent ?? WeaveContainerAdapter.global;
    for (final WeaveExport<Object?> export in exports) {
      export.forwardTo(target, container);
    }
    return true;
  }

  /// Instala os binds em um container específico.
  ///
  /// **Rebind destrutivo**, ao contrário de [install]: não é idempotente e
  /// não marca o módulo como instalado. Chamar duas vezes com o mesmo alvo
  /// substitui os registros e descarta os singletons já criados.
  void installInto(WeaveContainer targetContainer) {
    for (final WeaveModule module in _graph()) {
      for (final WeaveBind bind in module.binds) {
        bind(targetContainer);
      }
    }
  }

  /// Instala os binds no container global.
  void installGlobal() => installInto(WeaveContainerAdapter.global);

  /// Descarta o escopo do módulo e permite reinstalar.
  ///
  /// Após isto, [container] devolve um escopo novo — e não o cadáver
  /// desligado do pai.
  void disposeContainer() {
    final WeaveContainer? current = _container;
    if (current == null) {
      _installed = false;
      return;
    }
    final WeaveContainer effectiveParent =
        _parent ?? WeaveContainerAdapter.global;
    // Retira os encaminhamentos antes de matar o escopo: deixá-los apontaria
    // o pai para um container morto.
    for (final WeaveExport<Object?> export in exports) {
      export.revokeFrom(effectiveParent);
    }
    effectiveParent.disposeScope(current);
    _container = null;
    _installed = false;
  }

  @override
  String toString() => 'WeaveModule($name)';
}

/// Registry centralizado de módulos.
///
/// Gerencia lifecycle e dependências entre módulos.
///
/// ```dart
/// final registry = WeaveModuleRegistry();
/// registry.register(AuthModule());
/// registry.register(HomeModule());
/// await registry.installAll();
/// ```
class WeaveModuleRegistry {
  final Map<String, WeaveModule> _modules = <String, WeaveModule>{};
  final List<WeaveModule> _order = <WeaveModule>[];

  /// Registra um módulo. Nome duplicado é erro.
  void register(WeaveModule module) {
    final WeaveModule? existing = _modules[module.name];
    if (existing != null) {
      if (identical(existing, module)) return;
      throw StateError(
        'Já existe um módulo registrado com o nome "${module.name}".',
      );
    }
    _modules[module.name] = module;
    _order.add(module);
  }

  /// Obtém um módulo por nome.
  T get<T extends WeaveModule>(String name) {
    final WeaveModule? module = _modules[name];
    if (module is T) return module;
    throw StateError('Module "$name" not found or wrong type');
  }

  /// Instala todos os módulos registrados, em ordem topológica.
  ///
  /// `onInit` roda exatamente uma vez por módulo do grafo — incluindo
  /// imports que não foram registrados diretamente, que antes nunca eram
  /// inicializados.
  Future<void> installAll() async {
    for (final WeaveModule module in _resolvedOrder()) {
      if (module._installSelf()) {
        await module.onInit();
      }
    }
  }

  /// Descarta todos, na ordem inversa da instalação.
  Future<void> disposeAll() async {
    for (final WeaveModule module in _resolvedOrder().reversed) {
      if (!module.isInstalled) continue;
      await module.onDispose();
      module.disposeContainer();
    }
    _modules.clear();
    _order.clear();
  }

  /// Limpa o registry sem descartar módulos.
  void clear() {
    _modules.clear();
    _order.clear();
  }

  /// Todos os módulos registrados, na ordem de registro.
  List<WeaveModule> get modules => List<WeaveModule>.unmodifiable(_order);

  /// Todas as rotas de todos os módulos, sem duplicar módulo compartilhado.
  List<WeaveRoute> get allRoutes {
    final List<WeaveRoute> result = <WeaveRoute>[];
    for (final WeaveModule module in _resolvedOrder()) {
      result.addAll(module.routes);
    }
    return result;
  }

  /// Ordem topológica sobre o grafo inteiro, deduplicada por identidade.
  List<WeaveModule> _resolvedOrder() {
    final List<WeaveModule> ordered = <WeaveModule>[];
    final Set<WeaveModule> seen = Set<WeaveModule>.identity();
    for (final WeaveModule root in _order) {
      for (final WeaveModule module in root._graph()) {
        if (seen.add(module)) ordered.add(module);
      }
    }
    return ordered;
  }
}
