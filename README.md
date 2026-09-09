**English** · [Português](README.pt-BR.md)

# Weave

[![pub package](https://img.shields.io/pub/v/weave_di.svg)](https://pub.dev/packages/weave_di)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

> A DI + routing framework for Flutter, written because I was tired of
> boilerplate.

MIT. Copyright (c) 2026 Mateus Siqueira. Versions 3.0.0 through 3.3.0 went out
as proprietary; from 3.4.0 onwards the package is MIT again, and that is how it
stays.

## Why Weave?

I started this because every Flutter app I worked on had the same problem:

- DI containers either overcomplicated or too simple
- Navigation scattered everywhere
- Modules that felt like a mess

Weave solves that with a simple approach: **a lean DI container** + **a typed
routing system** + **modules with a lifecycle**. No magic, no excessive
boilerplate.

## Installation

```yaml
dependencies:
  weave_di: ^3.4.0
```

```bash
flutter pub get
```

## Quick start

### 1. Setting up the container

```dart
import 'package:weave_di/weave_di.dart';

// The global container is ready to use
WeaveContainerAdapter.global.bindSingleton<AuthService>(
  () => AuthServiceImpl(),
);

// Or create an isolated one for a module
final container = WeaveContainerAdapter.create(name: 'auth');
container.bindSingleton<UserService>(() => UserServiceImpl());
```

### 2. Defining routes

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
    // Query params work too
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

### 3. Wiring it into MaterialApp

```dart
MaterialApp(
  onGenerateRoute: appRouter.routeFactory,
  onGenerateInitialRoutes: appRouter.onGenerateInitialRoutes,
  initialRoute: '/',
);
```

> Use `initialRoute` with `/` registered in the router, **not** `home:`. The
> widget passed to `home:` does not go through `onGenerateRoute`, and
> therefore escapes guards, middlewares and redirects.
>
> `onGenerateInitialRoutes` matters as well: without it, a deep link to
> `/user/42` is split by Flutter into `/`, `/user` and `/user/42`, and all
> three become stacked pages.

## Features

### Dependency injection

```dart
final c = WeaveContainerAdapter(name: 'my-app');

// Singleton — one instance only
c.bindSingleton<AuthService>(() => AuthServiceImpl());

// Transient — a new instance on every call
c.bind<UserRepository>(() => UserRepositoryImpl());

// Lazy — created only when you ask
c.bindLazy<CacheService>(() => CacheServiceImpl());

// Instance — a value that already exists
c.bindInstance<Config>(appConfig);

// Factory with parameters (1 to 3)
c.bindFactory<UserRepository, Database>(
  (db) => UserRepositoryImpl(db: db),
);
final repo = c.get1<UserRepository, Database>(database);

// Async singleton
await c.bindSingletonAsync<Config>(() async => await loadConfig());

// Resolving
final auth = c.get<AuthService>();
final repo = c.get1<UserRepository, Database>(db);

// Override for tests
c.overrideFactory<AuthService>(() => MockAuthService());
```

### Scoped bindings

```dart
final scope = c.createScope(onDispose: () {
  // Cleanup when the scope is discarded
});

scope.bindSingleton<RequestContext>(() => RequestContext());
scope.get<RequestContext>(); // works

c.disposeScope(scope);
// scope.get<RequestContext>(); // Error
```

### Circular dependency detection

Weave detects circular dependencies automatically and throws a `StateError`:

```dart
c.bindLazy<String>(() => 'Depends on int: ${c.get<int>()}');
c.bindLazy<int>(() => c.get<String>().length);

c.get<String>(); // StateError: Circular dependency detected: String -> int -> String
```

### Typed routes

```dart
WeaveRoute(
  path: '/user/:id',
  builder: (context, params) {
    final id = params.getInt('id');        // type-safe
    final name = params.getString('name');
    final active = params.getBool('active');
    final tags = params.getList('tags');    // comma-separated
    final date = params.getDateTime('date');
    return UserPage(id: id);
  },
);
```

### Authorisation guards

```dart
// Custom guard
final authGuard = WeaveGuard.custom(
  canActivate: (context, route, params, matchedRoutes) async {
    final auth = context.get<AuthService>();
    return auth.isAuthenticated;
  },
);

// Built-in authentication guard
final authGuard = WeaveGuard.auth(
  isAuthenticated: (context) => context.get<AuthService>().isAuthenticated,
  loginPath: '/login',
);

// Always allow / always deny
WeaveGuard.allow();
WeaveGuard.deny();

// Applying it to a route
WeaveRoute(
  path: '/admin',
  builder: (_, _) => const AdminPage(),
  guards: [authGuard],
);
```

Since 2.1.0 guards run **in `onGenerateRoute` as well** — before that, only
programmatic navigation respected them, and a deep link walked straight into a
protected route. While the guard decides, the route shows
`guardPendingBuilder`; if it denies with nowhere to go back to, it shows
`guardBlockedBuilder`.

```dart
WeaveRouter(
  routes: routes,
  guardPendingBuilder: (_) => const Scaffold(body: Center(
    child: CircularProgressIndicator(),
  )),
  guardBlockedBuilder: (_) => const Scaffold(body: Center(
    child: Text('Access denied'),
  )),
);
```

#### Redirecting from a guard

A guard should not touch the `Navigator` on its own: during the `await`, the
top of the stack may no longer be its route. Implement
`WeaveRedirectingGuard` and return the decision:

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

Mark the destination with `skipGuards: true`, otherwise a **global** middleware
wraps `/login` itself and the redirect becomes a loop:

```dart
WeaveRoute(path: '/login', skipGuards: true, builder: (_, _) => LoginPage());
```

### Middleware

```dart
// Logging middleware
WeaveRouter(
  routes: [...],
  middlewares: [
    WeaveMiddleware.log(),
  ],
);

// Custom middleware
WeaveMiddleware.onNavigateAction(
  action: (context, path, params) async {
    analytics.trackNavigation(path);
    return true; // allows navigation
  },
);
```

### Redirects

```dart
WeaveRoute(
  path: '/old-page',
  redirect: (context, params) => '/new-page',
  builder: (_, _) => const SizedBox(), // never reached
);
```

### Nested routes

`children` declares the tree with a **relative** path; the router flattens it
into absolute paths at construction. Matching, params and query use the same
mechanism as flat routes.

```dart
WeaveRoute(
  path: '/stores',
  name: 'stores',
  builder: (_, _) => const StoreListPage(),
  children: [
    WeaveRoute(
      path: '/:slug',
      name: 'store',
      layoutBuilder: (context, child) => StoreShell(child: child),
      builder: (_, p) => StorePage(slug: p.getString('slug')),
      children: [
        WeaveRoute(path: '/categories/:cat', builder: ...),
        WeaveRoute(path: '/products/:id',    builder: ...),
      ],
    ),
  ],
);
// becomes /stores, /stores/:slug,
//         /stores/:slug/categories/:cat,
//         /stores/:slug/products/:id
```

A child **inherits guards and middlewares** from its ancestors: protecting
`/stores` protects the whole subtree. A module can declare its own subtree and
own it.

**`layoutBuilder`** wraps the route and its entire subtree — it is the store's
header that stays while you navigate between categories and products. It is
widget composition, not a nested Navigator: the stack is still one, and the
layout is rebuilt on each route.

**Breadcrumbs** come out of `match.ancestors`, with no string surgery:

```dart
final match = router.match('/stores/joe/products/42')!;
match.ancestors.map((r) => r.name);   // ['stores', 'store']
```

### Deep links into a hierarchy (web and modular apps)

Landing directly on `/notebooks/7/answers` — by URL on the web, by push
notification, or through the browser's back button — normally creates **one**
route, and back closes the app. With `stackAncestorsOnDeepLink` the whole
stack is built:

```dart
WeaveRouter(
  routes: routes,
  stackAncestorsOnDeepLink: true,
);
// /notebooks/7/answers  ->  [/notebooks, /notebooks/7, /notebooks/7/answers]
```

A segment with no registered route is skipped, not turned into a 404. The
query stays on the leaf only.

### Transitions

```dart
WeaveRoute(
  path: '/login',
  builder: (_, _) => const LoginPage(),
  transition: WeaveTransition.fade,
);

// Custom transition
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

### Modules with a lifecycle

`name`, `binds` and `routes` are constructor fields, not overridable getters:

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
    // Async initialisation (loading tokens, for instance)
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
// ... use the modules ...
await registry.disposeAll();
```

`installAll` resolves the order topologically from the `imports`, so
registration order does not matter. A module imported by two others is
installed once only — and `onInit` runs exactly once per module in the graph,
including for imports that were never registered directly.

A module's container is a **scope of the global one**: whatever is not
registered in it is resolved by walking up. For the module's routes to resolve
from it, pass the container to the router:

```dart
final router = WeaveRouter(
  routes: module.allRoutes,
  container: module.container,
);
```

### Diagnostics

Weave is **silent by default**. Up to 2.0.0 the container `print`ed on every
resolution, in release builds included.

```dart
// Turn logging on in debug only
WeaveLog.logger = kDebugMode ? WeaveLog.debugPrintLogger : null;

// Or per container/router
WeaveContainerAdapter.create(name: 'auth', logger: myLogger);
WeaveRouter(routes: routes, logger: myLogger);
```

### Navigation

```dart
// Passing the router explicitly
context.pushRoute(appRouter, '/user/42');
context.replaceRoute(appRouter, '/settings');
context.pushNamedRoute(appRouter, 'home');
context.popRoute();
context.popUntilRoot();
context.clearStackAndPush(appRouter, '/login');
```

### Testing

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

## API reference

### WeaveContainer
| Method | Description |
|--------|-------------|
| `bind<T>()` | Transient |
| `bindSingleton<T>()` | Singleton |
| `bindLazy<T>()` | Lazy singleton |
| `bindInstance<T>()` | A pre-built value |
| `bindFactory<T, A>()` | Factory with 1 param |
| `bindFactory2<T, A, B>()` | Factory with 2 params |
| `bindFactory3<T, A, B, C>()` | Factory with 3 params |
| `get<T>()` / `get1<T, A>()` / `get2<T, A, B>()` / `get3<T, A, B, C>()` | Resolve |
| `tryGet<T>()` | Nullable resolve |
| `unbind<T>()` | Removes a registration |
| `overrideFactory<T>()` | Override (for tests) |
| `createScope()` / `disposeScope()` | Scopes |
| `reset()` / `resetSingletons()` / `resetOverrides()` | Reset |

### WeaveRoute
| Property | Description |
|----------|-------------|
| `path` | Path with `:param` syntax |
| `name` | Name for named navigation |
| `builder` | Builder receiving `WeaveParams` |
| `guards` | Async authorisation guards |
| `middlewares` | Cross-cutting middleware |
| `transition` | Page transitions |
| `redirect` | Conditional redirect |
| `injectFactory` | Lazy injection |
| `children` | Nested routes |

### WeaveGuard
| Factory | Description |
|---------|-------------|
| `WeaveGuard.custom()` | Custom guard |
| `WeaveGuard.allow()` | Always allows |
| `WeaveGuard.deny()` | Always blocks |
| `WeaveGuard.auth()` | Authentication guard |

### WeaveMiddleware
| Factory | Description |
|---------|-------------|
| `WeaveMiddleware.log()` | Logging |
| `WeaveMiddleware.onNavigateAction()` | Custom action on navigation |
| `WeaveMiddleware.onRouteMatchedAction()` | Action when a route matches |

### WeaveRouter
| Method/Property | Description |
|-----------------|-------------|
| `routes` | Registered routes |
| `middlewares` | Global middlewares |
| `match(path)` | Finds the matching route |
| `canActivateRoute()` | Validates guards/middleware |
| `routeFactory` | For MaterialApp.onGenerateRoute |

### WeaveParams
| Method | Description |
|--------|-------------|
| `getString()` / `getInt()` / `getDouble()` / `getBool()` / `getList()` / `getDateTime()` | Typed access |
| `contains()` / `merge()` / `isEmpty` / `isNotEmpty` | Utilities |
| `==` / `hashCode` | Equality |

## Architecture

Weave is organised in layers:

```
lib/
├── weave_di.dart           # Barrel export
└── src/
    ├── container.dart         # WeaveContainer — the abstract interface
    ├── container_adapter.dart # WeaveContainerAdapter — the implementation
    ├── errors.dart            # the errors the container throws
    ├── export.dart            # what the barrel re-exports
    ├── gate.dart              # the gate a guard's decision passes through
    ├── guard.dart             # WeaveGuard — route authorisation
    ├── logger.dart            # WeaveLog — silent by default
    ├── middleware.dart        # WeaveMiddleware — interceptors
    ├── module.dart            # WeaveModule — organisation by feature
    ├── navigation.dart        # BuildContext extensions
    ├── route.dart             # WeaveRoute, WeaveParams, WeaveTransition
    └── router.dart            # WeaveRouter — the central manager
```

The reasoning behind those choices is in
[ARCHITECTURE.md](ARCHITECTURE.md), and worked examples in
[EXAMPLES.md](EXAMPLES.md).

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide.

## Licence

MIT. See [LICENSE](LICENSE).
