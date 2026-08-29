# Changelog

Todas as mudanças notáveis neste pacote são documentadas aqui.

O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/),
e este projeto adere ao [Semantic Versioning](https://semver.org/lang/pt-BR/).

---

## [3.3.0] - 2026-08-29

### Adicionado

- **`onInit` e `onDispose` pelo construtor do `WeaveModule`.**

  Os dois já existiam, mas só como métodos para sobrescrever — o que exige
  declarar o módulo como subclasse. Módulo declarado como função fábrica, que
  é a forma mais direta e a que o app de referência usa nos dezessete, não
  tinha como ter lifecycle. Na prática isso empurrava toda inicialização
  assíncrona para o `main`, que passava a conhecer o miolo de cada feature.

  ```dart
  WeaveModule(
    name: 'auth',
    binds: [...],
    onInit: (c) => c.get<AuthPresenter>().loadStoredUser(),
  )
  ```

  `onInit` roda depois dos binds do módulo e dos imports dele — o ponto em que
  o grafo está completo — e uma vez só, mesmo com `installAll` repetido. A
  ordem topológica vale: import inicializa antes de quem importa.

  **Não é breaking.** Quem declara o módulo como subclasse e sobrescreve
  continua funcionando; a sobrescrita substitui o callback do construtor, e
  `super.onInit()` mantém os dois.

---

## [3.2.0] - 2026-08-29

### Alterado

- **`WeaveRoute.builder` deixou de ser obrigatório** quando a rota declara
  `injectFactory`.

  `buildPage` sempre deu precedência ao `injectFactory`, mas `builder` era
  `required` — então toda rota que usava injeção precisava declarar um builder
  morto, que nunca rodava, só para satisfazer o construtor. Uma linha de ruído
  por rota, e o app de referência ia ganhar 23 delas.

  ```dart
  // antes: o builder existia só para o compilador aceitar
  WeaveRoute(
    path: '/reseller',
    builder: (_, _) => const SizedBox(),
    injectFactory: (context, params, c) => makeResellerPage(c),
  )

  // agora
  WeaveRoute(
    path: '/reseller',
    injectFactory: (context, params, c) => makeResellerPage(c),
  )
  ```

  **Não é breaking.** O campo continua não-nulável — torná-lo nulável quebraria
  quem lê `route.builder` e chama direto. Em vez disso o default é uma
  sentinela, e um `assert` no construtor exige que pelo menos um dos dois
  exista. Rota sem nenhum dos dois falha em debug, não em produção.

---

## [3.1.0] - 2026-08-28

### Adicionado

- **`WeaveModule.exports`** — o que faltava para `WeaveModule` ser utilizável
  num app com vários módulos.

  O container de um módulo é um **escopo**, e escopo resolve para cima, nunca
  de lado: sem export, o `HttpClient` registrado pelo módulo de autenticação
  era invisível para o de pagamentos. `imports` não resolvia isso — ele
  controla ordem de instalação, não visibilidade. Na prática, isso tornava
  impossível migrar um app real para `WeaveModule`, e era por isso que o app
  de referência tinha 16 classes estáticas escritas à mão.

  ```dart
  WeaveModule(
    name: 'auth',
    binds: [(c) => c.bindSingleton<HttpClient>(() => DioAdapter())],
    exports: [const WeaveExport<HttpClient>()],
  )
  ```

  O encaminhamento é **transient de propósito**: ele delega a
  `origem.get<T>()`, então o lifetime declarado no módulo é preservado — um
  singleton continua entregando a mesma instância dos dois lados, e um
  transient continua criando uma por chamada. Encaminhar como singleton
  cacheria no pai um tipo que o módulo declarou transient.

  `WeaveExport` aceita `name`, para binding nomeado. Descartar o módulo
  retira o encaminhamento do pai — deixá-lo apontaria para um escopo morto.

---

## [3.0.1] - 2026-08-28

Correções encontradas por auditoria adversarial sobre a própria 3.0.0. Duas
delas eram bloqueantes: **não use a 3.0.0**.

### Corrigido

- **Callback de `dispose` que lançava travava o container para sempre.**
  `_Binding.dispose()` notificava o callback **antes** de zerar o estado, e os
  laços de teardown não tinham `try/catch`. Um `close()` que lança — socket já
  fechado, `StreamController` fechado, plugin nativo no teardown — matava tudo
  que vinha depois: com cinco singletons e o terceiro lançando, três recursos
  vazavam e o `reset` relançava para sempre. Agora o estado é zerado antes de
  notificar, os erros são agregados e reportados no log, e o desmonte acontece
  de qualquer jeito. Escopo meio-descartado que continua resolvendo é pior que
  o erro.
- **`resetSingletons()` reentregava a instância que acabou de descartar.**
  Binding semeado por `bindInstance` ou `bindSingletonAsync` guarda
  `() => instance` como factory: descartar e manter o registro fazia o próximo
  `get` devolver o objeto morto. Agora o binding doado é invalidado no
  descarte, e resolver depois disso lança com instrução clara — o container
  não sabe reconstruir um objeto que recebeu pronto.
- **`validate()` deixava rastro.** O snapshot de "o que já estava
  instanciado" era tirado dentro do laço, então exercitar A cacheava B por
  tabela e, ao chegar em B, ele já constava como pré-existente — ficava vivo e
  sem `dispose`. O snapshot passou para antes do laço. Contradizia
  literalmente a doc do método.
- **`validate()` e `warmUp()` ignoravam `_overrides`.** Iteravam
  `_registrations` enquanto a resolução real usa `_overrides[key] ?? …`.
  Errava nas duas direções: override quebrado passava, e registro quebrado sob
  override bom reprovava — além de construir o objeto real por baixo do fake.
- **Ciclo em factory com argumento virava `StackOverflowError`.**
  `get1/get2/get3` ganharam `name` na 3.0.0 mas não entraram na pilha de
  resolução. Agora detectam ciclo como o `get`, e ganharam o mesmo guarda de
  argumento de tipo ausente.
- **`WeaveNotRegisteredError` era sempre construído na raiz**, então a
  mensagem listava só o container global e nenhum dos bindings vizinhos. Como
  `WeaveModule.container` é sempre um escopo, esse era o caminho padrão — e
  matava justamente o diagnóstico do erro que a 3.0.0 criou: o typo em `name`.
  O container de origem agora viaja na subida.
- **`warmUp()` não descia em escopos**, então eager declarado num módulo
  virava lazy na prática e `checked: 0` lia-se como "não há eager" em vez de
  "não olhei aí".
- **Nome numérico é rejeitado em debug.** `name: 1` e `name: 1.0` são a mesma
  chave em Dart, e o segundo bind substituía o primeiro em silêncio.

### Nota sobre a 3.0.0

Ela chegou a ser tagueada e enviada. A tag `v3.0.0` **não foi movida** — mover
tag publicada é o tipo de coisa que queima quem confia nela. Use `v3.0.1`.

---

## [3.0.0] - 2026-08-28

**Mudança de licença.** Da 3.0.0 em diante este software é **proprietário**.
As versões até a 2.2.0 foram distribuídas sob MIT; aquela concessão não é
revogada e não pode ser revogada retroativamente para as cópias já obtidas.
Ver `LICENSE`. Titular do copyright corrigido para Mateus Siqueira.

Distribuição por git com tag fixa, em repositório privado. Não há publicação
no pub.dev a partir desta versão.

### Quebra

- **`WeaveContainer` mudou.** Todo `bind*`/`get*` ganhou `{Object? name}`, e
  nasceram `bindEagerSingleton`, `canResolve`, `warmUp`, `validate` e
  `describe`. Em Dart, acrescentar membro ou parâmetro opcional a uma
  `abstract class` invalida o override de quem a implementa com `implements`
  — inclusive com corpo default. Quem tinha um fake de `WeaveContainer`
  escrito à mão precisa reimplementar; quem só **usa** o container não muda
  uma linha.
- **`tryGet` deixou de engolir tudo.** Agora só a ausência de registro devolve
  `null`. Ciclo e exceção lançada pela sua factory sobem. Silenciá-los
  escondia bug e desarmava a detecção de ciclo, porque a factory seguia
  rodando depois do erro.
- **`isRegistered` virou local.** Responde "está registrado *neste*
  container", sem subir para o pai. Para a pergunta antiga use `canResolve`.
  São perguntas diferentes e estavam confundidas numa só.
- **Shell routes removidas**: `WeaveShellRoute`, `WeaveShellOutlet`,
  `WeaveRoute.shell`, `isShell`, `shellBuilder` e `matchChild`. Nunca foram
  consumidas pelo router. O substituto é `layoutBuilder` + `children`, da
  2.2.0, que funciona.
- **`WeaveBinding` removido.** Era código órfão. Use `WeaveModule`.

### Adicionado

- **Bindings nomeados.** A chave do registro passou de `Type` para
  `(Type, Object?)`. Duas implementações do mesmo tipo convivem, e o nome pode
  ser qualquer objeto — `String`, enum, o que for.

  ```dart
  c.bindSingleton<HttpClient>(() => PublicClient(), name: 'public');
  c.bindSingleton<HttpClient>(() => AuthedClient(), name: 'authed');
  final client = c.get<HttpClient>(name: 'authed');
  ```

  Nome **não é curinga**: pedir sem nome não encontra um binding nomeado, e
  vice-versa. `_overrides` e a pilha de resolução usam a mesma chave.
- **Erros tipados** — `WeaveNotRegisteredError`,
  `WeaveCircularDependencyError` e `WeaveMissingTypeArgumentError`. Os dois
  primeiros estendem `StateError`, então `catch (StateError)` existente
  continua funcionando. A mensagem de "não registrado" agora diz **quais
  containers foram percorridos** e **o que existe neles** — antes só dizia o
  tipo que faltava, o que em um app com 16 módulos é caça ao tesouro.
- **`bindEagerSingleton` + `warmUp()`.** Eager de verdade, materializado por
  `warmUp` e não no momento do bind — no bind as dependências dele podem
  ainda não estar registradas. `warmUp` é idempotente e agrega as falhas em
  vez de parar na primeira. Até a 2.x `bindSingleton` e `bindLazy` eram
  idênticos e não existia eager nenhum, apesar da doc distinguir os dois.
- **`dispose` por binding.** `bindSingleton(factory, dispose: ...)` roda o
  callback quando a instância é descartada por `unbind`, `resetSingletons`,
  `reset`, `disposeScope` ou rebind. Instância que nunca foi criada não
  recebe dispose.
- **`validate()`** — percorre os registros, tenta resolver e devolve um
  `WeaveValidationReport` com faltantes, ciclos e factories que lançaram.
  Feito para rodar em teste: **instancia objetos de verdade**. Não deixa
  rastro — o que não existia antes da chamada é descartado no fim.
- **`describe()`**, **`lineage`** e **`registeredKeys`** para diagnóstico.
- **`canResolve<T>({Object? name})`** — a semântica que `isRegistered` tinha.

### Migração

Uso comum não muda: `bind*`, `get`, escopos e módulos continuam iguais, e o
parâmetro `name` é opcional em tudo. O que precisa de atenção:

| Se você… | Faça |
|---|---|
| implementava `WeaveContainer` à mão | reimplemente, ou estenda `WeaveContainerAdapter` |
| usava `isRegistered` esperando que subisse ao pai | troque por `canResolve` |
| dependia de `tryGet` engolindo qualquer erro | trate a exceção — ela indicava um bug |
| usava shell routes | `layoutBuilder` + `children` |
| usava `WeaveBinding` | `WeaveModule` |

---

## [2.2.0] - 2026-08-28

Rotas hierárquicas — o que `children` e as shell routes prometiam desde a
2.0.0 e nunca fizeram. Serve os dois casos que motivaram o desenho original:
web, onde a URL é a navegação (`/estabelecimentos/:slug/produtos/:id`), e app
modular, onde cada módulo é dono de uma subárvore (`/cadernos/:id/gabarito`).

### Adicionado

- **`WeaveRoute.children` agora é consumido pelo router.** A árvore é achatada
  na construção: filho declara path relativo, o router deriva o absoluto. Todo
  o mecanismo de casamento, params e query é o mesmo das rotas planas. Filho
  pode declarar com ou sem barra inicial.
- **Herança de guards e middlewares.** Proteger `/cadernos` protege
  `/cadernos/:id/gabarito`. O guard do avô entra uma vez só no neto.
- **`WeaveRoute.layoutBuilder`** — envolve a rota e a subárvore dela. É o
  cabeçalho da loja que permanece enquanto se navega entre categorias e
  produtos. Composição de widget, não Navigator aninhado: uma pilha só, e o
  layout é reconstruído a cada rota. Layouts aninhados se compõem do mais
  externo para o mais interno.
- **`WeaveRouteMatch.ancestors`** e **`WeaveRouter.ancestorsOf`** — a cadeia de
  pais, para breadcrumb sem cirurgia de string.
- **`WeaveRouter.flatRoutes`** — a árvore achatada, com paths absolutos e
  herança aplicada. `routes` continua devolvendo o que foi declarado.
- **`WeaveRouter.stackAncestorsOnDeepLink`** — deep link em folha passa a
  montar a pilha inteira, então o voltar sobe a árvore em vez de fechar o app.
  `/cadernos/7/gabarito` vira `/cadernos` → `/cadernos/7` →
  `/cadernos/7/gabarito`. Segmento sem rota é pulado; a query fica só na
  folha. `false` por padrão, porque numa declaração plana não há ancestral a
  empilhar.

### Depreciado

- `WeaveShellRoute`, `WeaveRoute.shell`, `isShell` e `shellBuilder` agora
  apontam para o substituto real: `layoutBuilder` + `children`. Antes a
  depreciação só dizia que não funcionavam.

### Corrigido

- A documentação pública ensinava `WeaveRoute.when` com `/reseller` e
  `brand.hasResellers` — o modelo de negócio de um app específico dentro de um
  package genérico. Trocado por feature flag.
- `description` do pubspec em inglês: é o snippet de busca do pub.dev.
- Topic `state-management` removido — contradizia a seção "O que não está no
  escopo" do próprio ARCHITECTURE.md e atraía a busca errada.

### Compatibilidade

Aditivo. Declaração plana continua idêntica, inclusive na identidade dos
objetos `WeaveRoute` em `flatRoutes`.

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
4. Módulo compartilhado é instalado uma vez só por `install()`/`installAll()`,
   mantendo a mesma instância. `installInto()` e `installGlobal()` continuam
   sendo rebind destrutivo — documentado no dartdoc.
5. Rota com guard ou middleware mostra um frame de `guardPendingBuilder`
   antes do conteúdo — `canActivateRoute` é assíncrono. Custo zero só existe
   quando o router não tem middleware global e a rota não tem guard nem
   middleware próprio.
6. **`pushNamedRoute` e `pushReplacementNamed` lançam `ArgumentError`** quando
   falta um `:param` — a 2.0.0 empurrava o path literal, com `:id` no lugar do
   valor, e a tela abria quebrada. Valor vazio conta como faltando. A exceção
   é síncrona: é erro de programação, não de runtime do usuário.
7. **Path param passou a ser decodificado.** `/user/a%2Fb` entrega `a/b` à
   página, alinhando com o que os query params já faziam. Quem decodificava
   manualmente vai decodificar duas vezes.

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
