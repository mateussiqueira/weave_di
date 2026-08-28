# Changelog

Todas as mudanças notáveis neste pacote são documentadas aqui.

O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/),
e este projeto adere ao [Semantic Versioning](https://semver.org/lang/pt-BR/).

---

## [2.0.0] - 2026-08-20

### O que mudou

Essa versão é uma reescrita completa. Eu refiz praticamente tudo porque a 1.0.0 tinha
muitas limitações que foram ficando óbvias conforme o projeto cresceu.

#### Container (DI)

- **Quebrou**: `WeaveContainer.instance` foi removido. Agora usa `WeaveContainerAdapter.global` ou `WeaveContainerAdapter.create()`.
- **Quebrou**: `override()` virou `overrideFactory()`. Faz mais sentido.
- **Quebrou**: Removidos `oldBind`, `oldBindSingleton`, `runInIsolate`. Não faziam sentido.
- **Novo**: Interface abstrata `WeaveContainer` pra testabilidade. Agora você pode trocar a implementação inteira se precisar.
- **Novo**: `unbind<T>()`, `tryGet<T>()`, `bindInstance<T>()`.
- **Novo**: Factories com parâmetros: `bindFactory<T, A>()`, `bindFactory2<T, A, B>()`, `bindFactory3<T, A, B, C>()`.
- **Novo**: Métodos de resolve correspondentes: `get1<T, A>()`, `get2<T, A, B>()`, `get3<T, A, B, C>()`.
- **Novo**: Detecção automática de dependências circulares. Lança `StateError` com a cadeia de dependências.
- **Novo**: `createScope()` aceita callback `onDispose` pra cleanup.
- **Novo**: Logging integrado com nome do container pra debug.

#### Rotas

- **Quebrou**: Builder agora recebe `WeaveParams` (tipo-safe) em vez de `Map<String, String>`.
- **Quebrou**: Removido `builderWithArgs` e a classe duplicada `ExtractQueryParams`.
- **Novo**: `redirect` condicional em rotas.
- **Novo**: `children` pra rotas aninhadas.
- **Novo**: `isShell` e `shellBuilder` integrados na `WeaveRoute`.
- **Novo**: `WeaveParams` ganhou `getDateTime()`, `merge()`, `isEmpty`, `isNotEmpty`, `==`, `hashCode`.

#### Guards

- **Quebrou**: Renomeado de `RouteGuard` pra `WeaveGuard`.
- **Quebrou**: `canActivate` agora é `Future<bool>` (assíncrono). Precisei disso pra guards de auth real.
- **Novo**: Factory methods: `WeaveGuard.custom()`, `.allow()`, `.deny()`, `.auth()`.

#### Middleware

- **Novo**: Sistema de middleware com `onNavigate()` e `onRouteMatched()`.
- **Novo**: Factory methods: `WeaveMiddleware.log()`, `.onNavigateAction()`, `.onRouteMatchedAction()`.

#### Router

- **Novo**: `middlewares` globais no `WeaveRouter`.
- **Quebrou**: `routeFactory` agora suporta redirect.
- **Melhor**: Logging opcional via callback.

#### Navegação

- **Quebrou**: Todos os métodos agora recebem `WeaveRouter` como parâmetro. Eliminei o estado global `WeaveRouter.current`.
- **Quebrou**: Removidos `maybePop`, `clearStackAndPushNamed`, `pushTo`, `replaceWith`.

#### Módulos

- **Quebrou**: `WeaveModule` agora é abstract com lifecycle (`onInit()`, `onDispose()`).
- **Novo**: `WeaveModuleRegistry` pra gerenciar múltiplos módulos.
- **Novo**: `installInto()` e `installGlobal()`.

#### Shell Routes

- **Quebrou**: `WeaveShellOutlet` agora aceita `childBuilder` pra customização.

#### Removido

- `routes_registry.dart` inteiro (`WeaveRoutes`, `WeaveRouterModule`, `createRouter`). Não fazia sentido manter.

### Novas Features

- Container abstrato pra testabilidade total.
- Factories tipadas com 1, 2, 3 parâmetros.
- Middleware system pra logging, analytics e redirecionamento.
- Redirect condicional em rotas.
- Rotas aninhadas via `children`.
- Shell routes integradas na `WeaveRoute`.
- Lifecycle hooks em módulos (`onInit`, `onDispose`).
- Registry de módulos com gerenciamento centralizado.
- `WeaveParams` rico com `getDateTime()`, `merge()`, equality.
- Logging opcional no container e router.

### Bugs corrigidos

- Detecção de dependências circulares agora funciona corretamente.
- Scopes não vazavam memória ao serem descartados.
- `tryGet` não lançava exceção para tipos não registrados.

---

## [1.0.0] - 2026-08-21

### Lançamento inicial

- Container de DI com singleton, transient, lazy e instance binding.
- Sistema de rotas com path params e query params.
- Guards de autorização básicos.
- Transições de página (material, cupertino, fade, slide, scale).
- Navegação via extensões de BuildContext.
- Shell routes pra layouts persistentes.
