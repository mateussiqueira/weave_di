**English** · [Português](CONTRIBUTING.pt-BR.md)

# Contributing to Weave

Thanks for wanting to contribute. This document explains how to take part.

## How to contribute

### 1. Fork the repository

```bash
git clone https://github.com/<your-user>/weave_di.git
cd weave_di
flutter pub get
```

### 2. Create a branch

```bash
git checkout -b feature/the-new-thing
```

Use a descriptive name:

- `feature/the-feature-name`
- `fix/the-bug-description`
- `docs/what-changed`
- `refactor/what-was-refactored`

### 3. Make your change

- Follow the project's style (see `analysis_options.yaml`)
- Add tests for new behaviour
- Update the documentation when it applies
- Keep the CHANGELOG current

### 4. Run the tests

```bash
flutter test
dart analyze
```

### 5. Open a pull request

- A clear, descriptive title
- Say what changed and why
- Reference issues when they apply
- Add screenshots if you changed UI

## Rules

### Code

- Run `dart format` before committing
- Do not add unnecessary dependencies
- Keep the package light (< 50KB compressed)
- No `print()` in production code — use the optional logger

### Tests

- Every new behaviour needs a test
- Unit tests first
- Widget tests when necessary
- Do not test the implementation, test the behaviour

### Documentation

- Every public API needs dartdoc
- The README has to be updated when the public API changes
- The CHANGELOG has to be updated for every release
- Documentation is bilingual: English on the canonical path
  (`README.md`, `ARCHITECTURE.md`, `CONTRIBUTING.md`, `EXAMPLES.md`) and
  Portuguese beside it (`*.pt-BR.md`). If you change one side, change the
  other, or say in the pull request that you could not.

### Commits

Use [Conventional Commits](https://www.conventionalcommits.org/), **in
English**:

```
feat: add a new feature
fix: correct a bug
docs: update the documentation
refactor: restructure code
test: add tests
chore: maintenance
```

## Project structure

```
lib/
├── weave_di.dart           # Barrel export
└── src/
    ├── container.dart         # WeaveContainer (interface)
    ├── container_adapter.dart # WeaveContainerAdapter (implementation)
    ├── errors.dart            # the errors the container throws
    ├── export.dart            # what the barrel re-exports
    ├── gate.dart              # the gate a guard's decision passes through
    ├── guard.dart             # WeaveGuard
    ├── logger.dart            # WeaveLog
    ├── middleware.dart        # WeaveMiddleware
    ├── module.dart            # WeaveModule
    ├── navigation.dart        # BuildContext extensions
    ├── route.dart             # WeaveRoute, WeaveParams
    └── router.dart            # WeaveRouter
```

## Development setup

### Prerequisites

- Flutter SDK >= 3.10.0
- Dart SDK >= 3.12.0

### Running

```bash
# Dependencies
flutter pub get

# Static analysis
dart analyze

# Tests
flutter test

# Tests with coverage
flutter test --coverage
```

### Test layout

The suite is organised by the version that introduced the behaviour, plus one
regression file that keeps the bugs already fixed from coming back:

```
test/
├── weave_unit_test.dart            # the container and the router, unit level
├── weave_2_1_0_test.dart           # guards in onGenerateRoute
├── weave_3_0_0_test.dart           # the 3.0.0 surface
├── weave_3_0_0_audit_test.dart     # what the 3.0.0 audit pinned
├── weave_exports_test.dart         # the barrel exports what it promises
├── weave_inject_factory_test.dart  # lazy injection on a route
├── weave_lifecycle_test.dart       # module onInit/onDispose and the graph
├── weave_nested_routes_test.dart   # the nested tree, flattening and breadcrumbs
└── weave_regression_test.dart      # one test per bug already fixed
```

## Issues and bugs

When reporting a bug, include:

1. The Weave version
2. The Flutter version
3. Steps to reproduce
4. Expected versus actual behaviour
5. The stack trace when it applies

## Feature requests

If you want a new feature, open an issue with:

1. A description of the problem
2. The proposed solution
3. Alternatives considered
4. The usage context

## Licence

By contributing, you agree your contributions are licensed under the MIT
licence.
