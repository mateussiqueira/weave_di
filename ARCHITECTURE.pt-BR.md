**Português** · [English](ARCHITECTURE.md)

# Arquitetura do Weave

Esse documento descreve as decisões de design por trás do Weave. Se você está pensando em contribuir ou quer entender por que as coisas são do jeito que são, leia aqui.

## Visão Geral

O Weave foi desenhado pra resolver dois problemas que eu via constantemente em apps Flutter:

1. **DI complexo demais** — muitos containers, muita configuração, difícil de testar
2. **Navegação espalhada** — rotas definidas em mil lugares, sem consistência

A solução foi criar um framework que seja **simples o suficiente pra usar no dia a dia**, mas **poderoso o suficiente pra escalar**.

## Princípios de Design

### 1. Simplicidade sobre Flexibilidade

Eu poderia ter feito um container super flexível com scopes aninhados, interceptors, lifecycle hooks complexos, etc. Mas a realidade é que 90% dos casos de uso precisam de:
- Singleton
- Transient
- Lazy
- Instance

O resto é edge case. Então o container foi desenhado pra ser **ótimo nos casos comuns** e **bom nos casos complexos**.

### 2. Type-Safety em Tudo

Toda vez que você usa `WeaveParams`, os dados vêm tipados. Não tem `Map<String, String>` solto no código. Isso evita bugs em runtime que são difíceis de debugar.

### 3. Zero Estado Global

Na 1.0.0, eu tinha um `WeaveRouter.current` global. Parecia conveniente, mas causava problemas:
- Difícil de testar
- Confuso em multi-navigator
- Race conditions em navegação assíncrona

Na 2.0.0, todo método de navegação recebe o `WeaveRouter` como parâmetro. Mais verboso, mas muito mais seguro.

### 4. Composição sobre Herança

O `WeaveModule` é uma classe concreta que você pode estender, mas também pode compor. Os `binds` são funções, não métodos abstratos. Isso permite padrões como:

```dart
final module = WeaveModule(
  name: 'feature',
  binds: [
    (c) => c.bindSingleton<Repo>(() => RepoImpl()),
    (c) => c.bind<UseCase>(() => UseCaseImpl()),
  ],
);
```

### 5. Testabilidade como Prioridade

A interface `WeaveContainer` foi criada especificamente pra permitir troca de implementação:

```dart
// Em testes
final container = MockContainer();
// Ou
final container = WeaveContainerAdapter(name: 'test');
container.overrideFactory<AuthService>(() => MockAuthService());
```

## Decisões de Implementação

### Por que `Function?` no `_Binding`?

Eu usei `Function?` internamente pra evitar generics complexos. O Dart não tem reified generics em runtime, então eu preciso usar closures pra capturar os tipos:

```dart
class _Binding<T> {
  final Function? _factory0;
  
  dynamic resolve0() {
    return (_factory0 as WeaveFactory<T>)();
  }
}
```

Isso permite que o container funcione com qualquer tipo sem precisar de `Map<Type, dynamic>` (que é inseguro).

### Por que não usar `get_it` ou `provider`?

Eu não queria depender de pacotes externos pro DI. O `get_it` é ótimo, mas:
- Não tem scopes com lifecycle
- Não tem detecção de circulares
- Não tem factories com parâmetros

E eu não queria puxar uma dependência pesada pra algo que eu podia fazer com ~200 linhas.

### Por que o router é baseado em `onGenerateRoute`?

O Flutter não tem um navigator 2.0 estável ainda. O `onGenerateRoute` é o padrão e funciona bem. Quando o Navigator 2.0 estiver pronto, eu posso adicionar suporte sem quebrar a API.

### Por que middlewares são assíncronos?

Porque na vida real, middleware precisa de:
- Analytics (pode ser async)
- Logging (pode ser async)
- Checagem de auth (async)
- Tracking (async)

Se fosse síncrono, você não poderia fazer nada útil.

## Estrutura de Módulos

Os módulos são uma camada de organização, não de abstração. Eles:
- Agrupam binds relacionados
- Agrupam rotas relacionadas
- Têm lifecycle (`onInit`, `onDispose`)
- Podem ser compostos via imports

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

## Layouts persistentes

O problema de um layout que permanece enquanto o conteúdo muda — bottom nav,
sidebar, o cabeçalho de uma loja — é resolvido pelo `layoutBuilder` numa rota
aninhada. Ele envolve a rota e toda a subárvore dela, e é composição de
widget, não Navigator aninhado: a pilha continua sendo uma só, e o layout é
reconstruído a cada rota.

Uma tentativa anterior disso saiu como `WeaveShellRoute`, com `isShell`,
`shellBuilder` e um caminho de casamento separado. Era **código morto**: o
router nunca consumiu nada daquilo. Foi depreciado na 2.1.0 e removido na
3.0.0, e o `layoutBuilder` é o que tomou o lugar. Este parágrafo existe porque
o documento descrevia o shell como se ele funcionasse, por duas versões depois
de ele deixar de existir.

## Transições

O sistema de transições é uma camada fina sobre `PageRouteBuilder`. Não tentei reinventar a roda — apenas provei uma API mais simples:

```dart
// Em vez de
PageRouteBuilder(
  pageBuilder: (_, __, ___) => Page(),
  transitionsBuilder: (_, animation, __, child) {
    return FadeTransition(opacity: animation, child: child);
  },
);

// Você escreve
WeaveRoute(
  transition: WeaveTransition.fade,
  builder: (_) => Page(),
);
```

## O que não está no escopo

- **State management** — Weave é DI + rotas, não Redux/BLoC/Riverpod
- **Injeção automática** — eu prefério explícito sobre implícito
- **Code generation** — sem build_runner, sem annotations mágicas
- **Hot reload avançado** — isso é responsabilidade do Flutter

## Futuro

Coisas que eu gostaria de adicionar (sem prometer):

- Navigator 2.0 (quando estiver estável)
- Deep linking mais robusto
- Analytics middleware embutido
- Test helpers pra routing
- Revisão do container: bindings nomeados, `validate()` do grafo,
  singleton eager, erros tipados e dispose por binding. Tudo isso muda a
  interface `WeaveContainer`, e em Dart isso quebra quem usa `implements`.

---

Se você discorda de alguma decisão, me avise! Eu aberto a discussão.
