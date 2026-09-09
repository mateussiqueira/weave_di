**English** · [Português](ARCHITECTURE.pt-BR.md)

# Weave's architecture

This document describes the design decisions behind Weave. If you are thinking
about contributing, or want to understand why things are the way they are, read
this.

## Overview

Weave was designed to solve two problems I kept seeing in Flutter apps:

1. **DI that is too complex** — too many containers, too much configuration,
   hard to test
2. **Navigation scattered everywhere** — routes defined in a thousand places,
   with no consistency

The answer was a framework **simple enough to use day to day** and **powerful
enough to scale**.

## Design principles

### 1. Simplicity over flexibility

I could have built a hugely flexible container with nested scopes,
interceptors, complex lifecycle hooks and so on. But the reality is that 90% of
use cases need:

- Singleton
- Transient
- Lazy
- Instance

The rest are edge cases. So the container was designed to be **excellent at the
common cases** and **good at the complex ones**.

### 2. Type safety everywhere

Every time you use `WeaveParams`, the data comes typed. There is no loose
`Map<String, String>` in the code. That avoids runtime bugs that are hard to
debug.

### 3. Zero global state

In 1.0.0 there was a global `WeaveRouter.current`. It looked convenient, and it
caused problems:

- hard to test
- confusing with multiple navigators
- race conditions in async navigation

In 2.0.0 every navigation method takes the `WeaveRouter` as a parameter. More
verbose, and much safer.

### 4. Composition over inheritance

`WeaveModule` is a concrete class you can extend, but you can also compose it.
The `binds` are functions, not abstract methods. That allows patterns like:

```dart
final module = WeaveModule(
  name: 'feature',
  binds: [
    (c) => c.bindSingleton<Repo>(() => RepoImpl()),
    (c) => c.bind<UseCase>(() => UseCaseImpl()),
  ],
);
```

### 5. Testability as a priority

The `WeaveContainer` interface exists specifically to allow swapping the
implementation:

```dart
// In tests
final container = MockContainer();
// Or
final container = WeaveContainerAdapter(name: 'test');
container.overrideFactory<AuthService>(() => MockAuthService());
```

## Implementation decisions

### Why `Function?` inside the binding?

I used `Function?` internally to avoid complex generics. Dart has no reified
generics at runtime, so I need closures to capture the types:

```dart
class _Binding<T> {
  final Function? _factory0;

  dynamic resolve0() {
    return (_factory0 as WeaveFactory<T>)();
  }
}
```

That lets the container work with any type without needing a
`Map<Type, dynamic>`, which is unsafe.

### Why not use `get_it` or `provider`?

I did not want an external dependency for DI. `get_it` is good, but:

- it has no scopes with a lifecycle
- it has no circular-dependency detection
- it has no factories with parameters

And I did not want to pull in a heavy dependency for something I could write in
about 200 lines.

### Why is the router based on `onGenerateRoute`?

Flutter still has no stable Navigator 2.0. `onGenerateRoute` is the standard
and works well. When Navigator 2.0 is ready, support can be added without
breaking the API.

### Why are middlewares asynchronous?

Because in real life, middleware needs:

- analytics (can be async)
- logging (can be async)
- auth checks (async)
- tracking (async)

If it were synchronous, you could not do anything useful.

## Module structure

Modules are a layer of organisation, not of abstraction. They:

- group related binds
- group related routes
- have a lifecycle (`onInit`, `onDispose`)
- can be composed through imports

```
App
├── AuthModule
│   ├── binds: [AuthService, AuthRepository]
│   └── routes: [/login, /register]
├── HomeModule
│   ├── binds: [HomeService]
│   ├── routes: [/home, /profile]
│   └── imports: [AuthModule]
└── FeatureModule
    ├── binds: [FeatureService]
    ├── routes: [/feature/:id]
    └── imports: [AuthModule, HomeModule]
```

## Persistent layouts

The problem of a layout that stays put while the content changes — a bottom
nav, a sidebar, a store header — is solved by `layoutBuilder` on a nested
route. It wraps the route and its entire subtree, and it is widget composition
rather than a nested Navigator: the stack remains one, and the layout is
rebuilt on each route.

An earlier attempt at this shipped as `WeaveShellRoute`, with `isShell`,
`shellBuilder` and a separate matching path. It was **dead code**: the router
never consumed any of it. It was deprecated in 2.1.0 and removed in 3.0.0, and
`layoutBuilder` is what took its place. This paragraph exists because the
document described the shell as though it worked, for two versions after it
stopped existing.

## Transitions

The transition system is a thin layer over `PageRouteBuilder`. I did not try to
reinvent the wheel — I only provided a simpler API:

```dart
// Instead of
PageRouteBuilder(
  pageBuilder: (_, __, ___) => Page(),
  transitionsBuilder: (_, animation, __, child) {
    return FadeTransition(opacity: animation, child: child);
  },
);

// You write
WeaveRoute(
  transition: WeaveTransition.fade,
  builder: (_) => Page(),
);
```

## Out of scope

- **State management** — Weave is DI + routing, not Redux/BLoC/Riverpod
- **Automatic injection** — I prefer explicit over implicit
- **Code generation** — no build_runner, no magic annotations
- **Advanced hot reload** — that is Flutter's responsibility

## Future

Things I would like to add, without promising:

- Navigator 2.0, once it is stable
- More robust deep linking
- A built-in analytics middleware
- Test helpers for routing
- A container revision: named bindings, a `validate()` over the graph, eager
  singletons, typed errors and per-binding dispose. All of that changes the
  `WeaveContainer` interface, and in Dart that breaks whoever uses
  `implements`.

---

If you disagree with a decision, say so. I am open to the discussion.
