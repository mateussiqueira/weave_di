# Weave

> Um framework de DI + rotas pra Flutter que eu criei porque estava cansado de boilerplate.

[![pub package](https://img.shields.io/pub/v/weave.svg)](https://pub.dev/packages/weave)
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
  weave: ^2.0.0
```

Depois é só rodar:

```bash
flutter pub get
```

## Quick Start

### 1. Configurando o Container

```dart
import 'package:weave/weave.dart';

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
  home: const HomePage(),
);
```

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
  builder: (_) => const AdminPage(),
  guards: [authGuard],
);
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
  builder: (_) => const SizedBox(), // nunca chega aqui
);
```

### Rotas Aninhadas

```dart
WeaveRoute(
  path: '/dashboard',
  builder: (context, params) => const DashboardLayout(),
  children: [
    WeaveRoute(path: '/stats', builder: (_, __) => StatsPage()),
    WeaveRoute(path: '/settings', builder: (_, __) => SettingsPage()),
  ],
);
```

### Shell Routes

```dart
WeaveShellRoute(
  path: '/app',
  shellBuilder: (context, child) => Scaffold(
    body: child,
    bottomNavigationBar: BottomNavigationBar(...),
  ),
  routes: [
    WeaveRoute(path: '/home', builder: (_, __) => HomePage()),
    WeaveRoute(path: '/settings', builder: (_, __) => SettingsPage()),
  ],
);
```

### Transições

```dart
WeaveRoute(
  path: '/login',
  builder: (_) => const LoginPage(),
  transition: WeaveTransition.fade,
);

// Transição customizada
WeaveRoute(
  path: '/animated',
  builder: (_) => const AnimatedPage(),
  transition: WeaveTransition(
    type: WeaveTransitionType.fade,
    duration: Duration(milliseconds: 500),
    curve: Curves.bounceIn,
  ),
);
```

### Módulos com Lifecycle

```dart
class AuthModule extends WeaveModule {
  @override
  String get name => 'auth';

  @override
  List<WeaveBind> get binds => [
    (c) => c.bindSingleton<AuthService>(() => AuthServiceImpl()),
  ];

  @override
  List<WeaveRoute> get routes => [
    WeaveRoute(path: '/login', builder: (_, __) => LoginPage()),
  ];

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
registry.register(HomeModule(imports: [registry.get<AuthModule>('auth')]));
await registry.installAll();
// ... usar módulos ...
await registry.disposeAll();
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
