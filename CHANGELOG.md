# Changelog

Todas as mudanças notáveis neste pacote são documentadas aqui.

O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/),
e este projeto adere ao [Semantic Versioning](https://semver.org/lang/pt-BR/).

---

## [2.1.0] - 2026-08-28

Release de correções. Nada da interface `WeaveContainer` foi tocado, de
propósito: em Dart, acrescentar membro ou parâmetro opcional a uma
`abstract class` quebra **todo** mundo que a implementa com `implements` —
inclusive com corpo default. A revisão do container (bindings nomeados,
`validate()`, singleton eager, `isRegistered` consistente) ficou para a
3.0.0, com o rótulo honesto.

### Corrigido

- **Guards e middlewares não rodavam em `onGenerateRoute`.** `canActivateRoute`
  só era chamado pelas extensões de navegação. Deep link, rota inicial e
  `Navigator.pushNamed` entravam direto em rota protegida — `WeaveGuard.deny()`
  não bloqueava nada por esse caminho. Agora uma rota com guard ou middleware
  é embrulhada num gate que decide antes de construir a página.
- **Query params eram descartados no roteamento.** `WeaveRouter.match` usava
  `extractParams` (só `:param` de path) e nunca `extractAllParams`. O exemplo
  `?q=...&page=2` da própria README não funcionava. Em colisão, **path vence
  query** — o contrário deixaria um deep link sobrescrever o identificador que
  os guards inspecionam.
- **`WeaveParams.hashCode` violava o contrato de `==`.** Usava a identidade do
  `Map` enquanto `==` comparava conteúdo, então dois params iguais ocupavam
  duas posições num `Set`.
- **`extractQueryParams` lançava em URI truncada** (`?q=100%`), descartava
  flags sem valor (`?debug`) e não decodificava `+` como espaço. Reescrito
  sobre `Uri.splitQueryString`, com URI malformada virando mapa vazio em vez
  de derrubar a navegação.
- **A detecção de dependência circular se desarmava sozinha.** Ao detectar um
  ciclo, `get<T>` chamava `_resolutionStack.clear()`, apagando os frames de
  quem estava acima; combinado com `tryGet` engolindo o erro, a resolução
  seguia em recursão infinita. A pilha agora só é desmontada pelo `finally`
  de cada frame.
- **`unbind<T>()` não removia o override**, então o tipo continuava
  resolvendo depois de removido.
- **`WeaveModule` criava um container órfão.** Usava
  `WeaveContainerAdapter.create()`, que não define pai, então os binds do
  módulo eram inalcançáveis por qualquer outro container. Agora é um escopo
  do `parent` (global por padrão), configurável via `WeaveModule(parent:)`.
- **`install()` de módulo não era idempotente.** Um módulo importado por dois
  outros era instalado duas vezes, e o rebind descartava silenciosamente o
  singleton já criado.
- **`onInit` nunca rodava em import não registrado** no `WeaveModuleRegistry`.
- **`redirect` só era respeitado em `pushRoute`** — `replaceRoute` e
  `clearStackAndPush` ignoravam. Agora vale nos três, com teto de saltos
  (`maxRedirects`, padrão 5) e log ao abortar um laço.
- **Transições customizadas perdiam `RouteSettings`.** Toda rota com
  transição não-material chegava ao `Navigator` anônima, e nada que
  dependesse de `ModalRoute.of(context)?.settings` funcionava nela.
- **`WeaveTransitionType.none` animava por 300ms.** Agora é `Duration.zero`.
- **Barra final quebrava o match.** `/user/42/` não casava com `/user/:id`,
  embora deep link chegue com barra o tempo todo.
- **`disposeScope` não era recursivo** — escopos netos vazavam.
- **`_AuthWeaveGuard` navegava de dentro do `canActivate`** com
  `pushReplacementNamed`, que mira o topo da pilha e não a rota guardada: se
  o usuário empurrasse outra tela durante o `await`, destruía a errada.
- **README e EXAMPLES documentavam o package errado** (`weave` em vez de
  `weave_di`), com exemplos de `builder:` de um argumento que não compilam e
  uma classe de módulo com getters que não existem.

### Adicionado

- **`WeaveRoute.when`** — condição de existência avaliada a cada match. Com
  `false`, a rota não casa, não aparece na busca por nome e o path cai no
  tratamento de rota desconhecida. É a primitiva de "um codebase, N
  variantes": white-label, feature flag, tier, região.
- **`WeaveRouter.merge` / `WeaveRouter.mergeRoutes`** — compõe uma base com
  sobrescritas. Rota com `path` já existente substitui **no lugar dela**,
  preservando a ordem de declaração, que é a precedência do `match`.
- **`WeaveRouter.onUnknownRoute`** — tipado como
  `Route<dynamic>? Function(RouteSettings)`, então dá para escolher a
  transição ou devolver `null` e delegar ao Flutter.
- **`WeaveRouter.onGenerateInitialRoutes`** — sem ele, o Flutter quebra um
  deep link `/user/42` em `/`, `/user` e `/user/42` e empilha os três.
- **`WeaveRouter.container`** — o container de onde as rotas resolvem. É o
  que torna um `WeaveModule` com container próprio realmente utilizável.
- **`WeaveRouter.routeByName`** — busca por nome respeitando `when`.
- **`WeaveGuardResult` e `WeaveRedirectingGuard`** — um guard descreve a
  decisão (`allow` / `block` / `redirect`) em vez de mexer no `Navigator`.
  Interface **opcional**: `WeaveGuard` continua idêntico, nenhum guard
  existente quebra.
- **`WeaveRoute.skipGuards`** — impede o gate de embrulhar a rota. Use no
  destino de um redirect de guard: sem isso, um middleware global embrulha o
  próprio `/login` e o redirect vira laço estrutural.
- **`guardPendingBuilder` e `guardBlockedBuilder`** — construtores separados
  de propósito. Confundir os dois é o que produz tela branca definitiva.
- **`WeaveLog`** — interruptor único de diagnóstico, silencioso por padrão.
  `WeaveContainerAdapter` e `WeaveRouter` aceitam `logger` próprio.
- **`WeaveContainerAdapter.createScopeNamed`** — escopo com nome legível.
- **`WeaveParams.of`** — construtor com cópia defensiva.
- **`params:` em `pushNamedRoute` e `pushReplacementNamed`** — materializa os
  `:segmentos`. Antes, navegar por nome para `/user/:id` empurrava o path
  literal, com `:id` no lugar do valor.
- **`WeaveModule.disposeContainer`** e `isInstalled`.

### Alterado

- Os métodos de navegação (`pushRoute`, `replaceRoute`, `clearStackAndPush`,
  `pushNamedRoute`, `pushReplacementNamed`, `WeaveRouter.push`) devolvem
  `Future<T?>` em vez de `void`. Antes eram `void ... async`, então era
  literalmente impossível esperar a navegação. Compatível para chamadas como
  statement.
- `WeaveModuleRegistry.installAll` instala em ordem topológica pelos
  `imports`, não na ordem de registro; `disposeAll` descarta o escopo via
  `disposeScope` em vez de só resetar; nome duplicado no `register` agora é
  erro.
- `WeaveGuard.auth()` não navega mais sozinho — devolve
  `WeaveGuardResult.redirect`. Quem dependia do efeito colateral precisa
  passar a usar o gate.

### Depreciado

- `WeaveShellRoute`, `WeaveRoute.shell`, `isShell`, `shellBuilder` e
  `children`. **Nunca funcionaram**: nada em `router.dart` os referencia, e
  uma `WeaveRoute.shell` renderiza `SizedBox` vazio. A README e o CHANGELOG
  da 2.0.0 os documentavam como funcionais — erro corrigido aqui. Componha o
  shell dentro do builder da página.
- `WeaveBinding` — código órfão, não consumido por nenhuma outra parte do
  package. Use `WeaveModule`.

### Mudanças de comportamento observáveis

Nenhuma quebra de API, mas o comportamento muda em cinco pontos:

1. O package fica **calado**. Quem lia o `print` do container precisa
   atribuir `WeaveLog.logger`.
2. Query param **não sobrescreve mais** path param de mesmo nome.
3. Rotas com transição customizada passam a ter `name` e `arguments`.
4. Módulo compartilhado é instalado uma vez só, mantendo a mesma instância.
5. Rota com guard ou middleware mostra um frame de `guardPendingBuilder`
   antes do conteúdo — `canActivateRoute` é assíncrono. Custo zero só existe
   quando o router não tem middleware global e a rota não tem guard nem
   middleware próprio.

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
- **Novo**: `children` pra rotas aninhadas. *(Retratado na 2.1.0: o router
  nunca consumiu `children` — a rota filha jamais era construída.)*
- **Novo**: `isShell` e `shellBuilder` integrados na `WeaveRoute`.
  *(Retratado na 2.1.0: nunca foram integrados ao router.)*
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
