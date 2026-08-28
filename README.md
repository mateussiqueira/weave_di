# Weave

> Um framework de DI + rotas pra Flutter que eu criei porque estava cansado de boilerplate.

[![pub package](https://img.shields.io/pub/v/weave_di.svg)](https://pub.dev/packages/weave_di)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## Por que Weave?

Eu comecei esse projeto porque todo app Flutter que eu trabalhava tinha o mesmo problema:

- Containers de DI super complexos ou muito simples
- Navegação espalhada por toda parte
- Módulos que pareciam uma bagunça

Weave resolve isso com uma abordagem simples: **um container de DI enxuto** + **um sistema de rotas tipado** + **módulos com lifecycle**. Sem magia, sem boilerplate excessivo.

## Instalação

```yaml
dependencies:
  weave_di: ^2.1.0
```

Depois é só rodar:

```bash
flutter pub get
```

## Quick Start

### 1. Configurando o Container

```dart
import 'package:weave_di/weave_di.dart';

// O container global já vem pronto
WeaveContainerAdapter.global.bindSingleton<AuthService>(
  () => AuthServiceImpl(),
);

// Ou cria um isolado pra um módulo
final container = WeaveContainerAdapter.create(name: 'auth');
container.bindSingleton<UserService>(() => UserServiceImpl());
```

### 2. Definindo Rotas

```dart
final appRouter = WeaveRouter(
  routes: [
    WeaveRoute(
      path: '/',
      name: 'home',
      builder: (context, params) => const HomePage(),
    ),
    WeaveRoute(
      path: '/user/:id',
      name: 'user',
      builder: (context, params) => UserPage(
        userId: params.getInt('id'),
      ),
    ),
    // Query params funcionam também
    WeaveRoute(
      path: '/search',
      builder: (context, params) => SearchPage(
        query: params.getString('q'),
        page: params.getInt('page', fallback: 1),
      ),
    ),
  ],
);
```

### 3. Conectando no MaterialApp

```dart
MaterialApp(
  onGenerateRoute: appRouter.routeFactory,
  onGenerateInitialRoutes: appRouter.onGenerateInitialRoutes,
  initialRoute: '/',
);
```

> Use `initialRoute` com `/` registrada no router, **não** `home:`. O widget
> passado em `home:` não passa por `onGenerateRoute`, e portanto escapa de
> guards, middlewares e redirects.
>
> `onGenerateInitialRoutes` também importa: sem ele, um deep link `/user/42`
> é quebrado pelo Flutter em `/`, `/user` e `/user/42`, e os três viram
> páginas empilhadas.

## Funcionalidades

### Dependency Injection

```dart
final c = WeaveContainerAdapter(name: 'my-app');

// Singleton — uma instância só
c.bindSingleton<AuthService>(() => AuthServiceImpl());

// Transient — nova instância a cada chamada
c.bind<UserRepository>(() => UserRepositoryImpl());

// Lazy — criada só quando você pedir
c.bindLazy<CacheService>(() => CacheServiceImpl());

// Instance — valor que já existe
c.bindInstance<Config>(appConfig);

// Factory com parâmetros (1 a 3 params)
c.bindFactory<UserRepository, Database>(
  (db) => UserRepositoryImpl(db: db),
);
final repo = c.get1<UserRepository, Database>(database);

// Async singleton
await c.bindSingletonAsync<Config>(() async => await loadConfig());

// Resolvendo
final auth = c.get<AuthService>();
final repo = c.get1<UserRepository, Database>(db);

// Override pra testes
c.overrideFactory<AuthService>(() => MockAuthService());
```

### Scoped Bindings

```dart
final scope = c.createScope(onDispose: () {
  // Cleanup quando o scope for descartado
});

scope.bindSingleton<RequestContext>(() => RequestContext());
scope.get<RequestContext>(); // Funciona

c.disposeScope(scope);
// scope.get<RequestContext>(); // Error
```

### Detecção de Dependências Circulares

O Weave detecta automaticamente dependências circulares e lança um `StateError`:

```dart
c.bindLazy<String>(() => 'Depende de int: ${c.get<int>()}');
c.bindLazy<int>(() => c.get<String>().length);

c.get<String>(); // StateError: Circular dependency detected: String -> int -> String
```

### Rotas Tipadas

```dart
WeaveRoute(
  path: '/user/:id',
  builder: (context, params) {
    final id = params.getInt('id');        // tipo-safe
    final name = params.getString('name');
    final active = params.getBool('active');
    final tags = params.getList('tags');    // separado por vírgula
    final date = params.getDateTime('date');
    return UserPage(id: id);
  },
);
```

### Guards de Autorização

```dart
// Guard customizado
final authGuard = WeaveGuard.custom(
  canActivate: (context, route, params, matchedRoutes) async {
    final auth = context.get<AuthService>();
    return auth.isAuthenticated;
  },
);

// Guard de autenticação embutido
final authGuard = WeaveGuard.auth(
  isAuthenticated: (context) => context.get<AuthService>().isAuthenticated,
  loginPath: '/login',
);

// Sempre permitir/bloquear
WeaveGuard.allow();
WeaveGuard.deny();

// Aplicando à rota
WeaveRoute(
  path: '/admin',
  builder: (_, _) => const AdminPage(),
  guards: [authGuard],
);
```

Desde a 2.1.0 os guards rodam **também** em `onGenerateRoute` — antes só a
navegação programática os respeitava, e deep link entrava direto em rota
protegida. Enquanto o guard decide, a rota mostra `guardPendingBuilder`; se
negar sem ter para onde voltar, mostra `guardBlockedBuilder`.

```dart
WeaveRouter(
  routes: routes,
  guardPendingBuilder: (_) => const Scaffold(body: Center(
    child: CircularProgressIndicator(),
  )),
  guardBlockedBuilder: (_) => const Scaffold(body: Center(
    child: Text('Acesso negado'),
  )),
);
```

#### Redirect a partir de um guard

Um guard não deve mexer no `Navigator` por conta própria: durante o `await`
o topo da pilha pode não ser mais a rota dele. Implemente
`WeaveRedirectingGuard` e devolva a decisão:

```dart
class AuthGuard implements WeaveRedirectingGuard {
  @override
  Future<WeaveGuardResult> resolve(context, route, params, matched) async =>
      isLogged ? const WeaveGuardResult.allow()
               : const WeaveGuardResult.redirect('/login');

  @override
  Future<bool> canActivate(context, route, params, matched) async => isLogged;
}
```

Marque o destino com `skipGuards: true`, senão um middleware **global**
embrulha o próprio `/login` e o redirect vira laço:

```dart
WeaveRoute(path: '/login', skipGuards: true, builder: (_, _) => LoginPage());
```

### Middleware

```dart
// Middleware de log
WeaveRouter(
  routes: [...],
  middlewares: [
    WeaveMiddleware.log(),
  ],
);

// Middleware customizado
WeaveMiddleware.onNavigateAction(
  action: (context, path, params) async {
    analytics.trackNavigation(path);
    return true; // permite navegação
  },
);
```

### Redirects

```dart
WeaveRoute(
  path: '/old-page',
  redirect: (context, params) => '/new-page',
  builder: (_, _) => const SizedBox(), // nunca chega aqui
);
```

### Rotas Aninhadas

> **Não implementado.** `children` é aceito pela `WeaveRoute` mas o router
> não o consome — a rota filha nunca é construída. Depreciado na 2.1.0.

```dart
WeaveRoute(
  path: '/dashboard',
  builder: (context, params) => const DashboardLayout(),
  children: [
    WeaveRoute(path: '/stats', builder: (_, _) => StatsPage()),
    WeaveRoute(path: '/settings', builder: (_, _) => SettingsPage()),
  ],
);
```

### Shell Routes

> **Não implementado.** Nada em `router.dart` referencia `WeaveShellRoute`,
> `isShell` ou `shellBuilder`; a rota renderiza um `SizedBox` vazio.
> Depreciado na 2.1.0 — componha o shell dentro do builder da página.

```dart
WeaveShellRoute(
  path: '/app',
  shellBuilder: (context, child) => Scaffold(
    body: child,
    bottomNavigationBar: BottomNavigationBar(...),
  ),
  routes: [
    WeaveRoute(path: '/home', builder: (_, _) => HomePage()),
    WeaveRoute(path: '/settings', builder: (_, _) => SettingsPage()),
  ],
);
```

### Rotas condicionais e composição de router

Um codebase que vira vários apps — white-label, feature flag, tier, região.

`when` decide se a rota existe, avaliado a cada match. Retornando `false`, ela
se comporta como se não estivesse registrada: não casa, não aparece na busca
por nome, e o path cai no tratamento de rota desconhecida.

```dart
WeaveRoute(
  path: '/reseller',
  when: () => brand.hasResellers,
  builder: (_, _) => const ResellerPage(),
);
```

`WeaveRouter.merge` compõe uma base com sobrescritas. Rota cujo `path` já
existe na base **substitui no lugar dela**, preservando a ordem de declaração
— o que importa, porque `match` devolve a primeira que casar e ordem é
precedência (`/user/new` declarada antes de `/user/:id` continua vencendo).
Path inédito é anexado ao fim.

```dart
final router = WeaveRouter.merge(
  base: appRoutes,
  overrides: brand.routeOverrides,
);
```

### Transições

```dart
WeaveRoute(
  path: '/login',
  builder: (_, _) => const LoginPage(),
  transition: WeaveTransition.fade,
);

// Transição customizada
WeaveRoute(
  path: '/animated',
  builder: (_, _) => const AnimatedPage(),
  transition: WeaveTransition(
    type: WeaveTransitionType.fade,
    duration: Duration(milliseconds: 500),
    curve: Curves.bounceIn,
  ),
);
```

### Módulos com Lifecycle

`name`, `binds` e `routes` são campos do construtor, não getters
sobrescrevíveis:

```dart
class AuthModule extends WeaveModule {
  AuthModule() : super(
    name: 'auth',
    binds: [
      (c) => c.bindSingleton<AuthService>(() => AuthServiceImpl()),
    ],
    routes: [
      WeaveRoute(path: '/login', builder: (_, _) => LoginPage()),
    ],
  );

  @override
  Future<void> onInit() async {
    // Inicialização assíncrona (ex: carregar tokens)
  }

  @override
  Future<void> onDispose() async {
    // Cleanup
  }
}

// Registry
final registry = WeaveModuleRegistry();
registry.register(AuthModule());
registry.register(HomeModule());
await registry.installAll();
// ... usar módulos ...
await registry.disposeAll();
```

`installAll` resolve a ordem topologicamente pelos `imports`, então a ordem de
registro não importa. Um módulo importado por dois outros é instalado uma vez
só — e `onInit` roda exatamente uma vez por módulo do grafo, inclusive para
imports que nunca foram registrados diretamente.

O container do módulo é um **escopo do global**: o que não estiver registrado
nele é resolvido subindo. Para que as rotas do módulo resolvam a partir dele,
passe o container ao router:

```dart
final router = WeaveRouter(
  routes: module.allRoutes,
  container: module.container,
);
```

### Diagnóstico

O Weave é **silencioso por padrão**. Até a 2.0.0 o container fazia um `print`
a cada resolução, inclusive em release.

```dart
// Liga o log só em debug
WeaveLog.logger = kDebugMode ? WeaveLog.debugPrintLogger : null;

// Ou por container/router
WeaveContainerAdapter.create(name: 'auth', logger: meuLogger);
WeaveRouter(routes: routes, logger: meuLogger);
```

### Navegação

```dart
// Passando router explicitamente
context.pushRoute(appRouter, '/user/42');
context.replaceRoute(appRouter, '/settings');
context.pushNamedRoute(appRouter, 'home');
context.popRoute();
context.popUntilRoot();
context.clearStackAndPush(appRouter, '/login');
```

### Testando

```dart
test('service works', () {
  final container = WeaveContainerAdapter(name: 'test');
  
  container.bindSingleton<AuthService>(() => MockAuthService());
  container.overrideFactory<AuthService>(() => MockAuthService());
  
  final auth = container.get<AuthService>();
  expect(auth, isA<MockAuthService>());
  
  container.reset();
});
```

## Referência da API

### WeaveContainer
| Método | Descrição |
|--------|-----------|
| `bind<T>()` | Transient |
| `bindSingleton<T>()` | Singleton |
| `bindLazy<T>()` | Lazy singleton |
| `bindInstance<T>()` | Valor pré-criado |
| `bindFactory<T, A>()` | Factory com 1 param |
| `bindFactory2<T, A, B>()` | Factory com 2 params |
| `bindFactory3<T, A, B, C>()` | Factory com 3 params |
| `get<T>()` / `get1<T, A>()` / `get2<T, A, B>()` / `get3<T, A, B, C>()` | Resolve |
| `tryGet<T>()` | Nullable resolve |
| `unbind<T>()` | Remove registro |
| `overrideFactory<T>()` | Override (testes) |
| `createScope()` / `disposeScope()` | Escopos |
| `reset()` / `resetSingletons()` / `resetOverrides()` | Reset |

### WeaveRoute
| Propriedade | Descrição |
|-------------|-----------|
| `path` | Path com sintaxe `:param` |
| `name` | Nome para navegação nomeada |
| `builder` | Builder com `WeaveParams` |
| `guards` | Guards de autorização assíncronos |
| `middlewares` | Middleware transversal |
| `transition` | Transições de página |
| `redirect` | Redirect condicional |
| `injectFactory` | Lazy injection |
| `children` | Rotas aninhadas |
| `shellBuilder` | Layout shell |

### WeaveGuard
| Factory | Descrição |
|---------|-----------|
| `WeaveGuard.custom()` | Guard customizado |
| `WeaveGuard.allow()` | Sempre permite |
| `WeaveGuard.deny()` | Sempre bloqueia |
| `WeaveGuard.auth()` | Guard de autenticação |

### WeaveMiddleware
| Factory | Descrição |
|---------|-----------|
| `WeaveMiddleware.log()` | Logging |
| `WeaveMiddleware.onNavigateAction()` | Ação customizada ao navegar |
| `WeaveMiddleware.onRouteMatchedAction()` | Ação ao encontrar rota |

### WeaveRouter
| Método/Propriedade | Descrição |
|---------------------|-----------|
| `routes` | Rotas registradas |
| `middlewares` | Middlewares globais |
| `match(path)` | Busca rota correspondente |
| `canActivateRoute()` | Valida guards/middleware |
| `routeFactory` | Para MaterialApp.onGenerateRoute |

### WeaveParams
| Método | Descrição |
|--------|-----------|
| `getString()` / `getInt()` / `getDouble()` / `getBool()` / `getList()` / `getDateTime()` | Acesso tipado |
| `contains()` / `merge()` / `isEmpty` / `isNotEmpty` | Utilidades |
| `==` / `hashCode` | Igualdade |

## Arquitetura

O Weave é organizado em camadas:

```
lib/
├── weave.dart              # Barrel export
└── src/
    ├── binding.dart        # WeaveBinding — registro de DI
    ├── container.dart      # WeaveContainer — interface abstrata
    ├── container_adapter.dart # WeaveContainerAdapter — implementação
    ├── guard.dart          # WeaveGuard — autorização de rotas
    ├── middleware.dart      # WeaveMiddleware — interceptadores
    ├── module.dart         # WeaveModule — organização por features
    ├── navigation.dart     # Extensões de BuildContext
    ├── route.dart          # WeaveRoute, WeaveParams, WeaveTransition
    ├── router.dart         # WeaveRouter — gerenciador central
    └── shell_route.dart    # WeaveShellRoute — layouts persistentes
```

## Contribuindo

Leia [CONTRIBUTING.md](CONTRIBUTING.md) para guia completo.

## Licença

MIT License — veja [LICENSE](LICENSE) para detalhes.
