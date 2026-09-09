**Português** · [English](CONTRIBUTING.md)

# Contribuindo pro Weave

Obrigado por querer contribuir! Esse documento explica como participar.

## Como Contribuir

### 1. Fork o Repositório

```bash
git clone https://github.com/<seu-usuario>/weave_di.git
cd weave_di
flutter pub get
```

### 2. Crie uma Branch

```bash
git checkout -b feature/nova-funcionalidade
```

Use um nome descritivo:
- `feature/nome-da-feature`
- `fix/descricao-do-bug`
- `docs/atualizacao-docs`
- `refactor/descricao-da-refatoracao`

### 3. Implemente sua Mudança

- Siga o estilo do projeto (veja `analysis_options.yaml`)
- Adicione testes pra funcionalidade nova
- Atualize a documentação se necessário
- Mantenha o CHANGELOG atualizado

### 4. rode os Testes

```bash
flutter test
dart analyze
```

### 5. Faça um Pull Request

- Título claro e descritivo
- Descreva o que mudou e por quê
- Referencie issues se aplicável
- Adicione screenshots se mudar UI

## Regras

### Código

- Use `dart format` antes de commitar
- Não adicione dependências desnecessárias
- Mantenha o package leve (< 50KB comprimido)
- Não use `print()` em código de produção (use logging opcional)

### Testes

- Toda funcionalidade nova precisa de testes
- Testes de unidade primeiro
- Testes de widget quando necessário
- Não teste implementação, teste comportamento

### Documentação

- Toda feature pública precisa de dartdoc
- README deve ser atualizado se mudar API pública
- CHANGELOG deve ser atualizado pra cada release
- A documentação é bilíngue: inglês no caminho canônico
  (`README.md`, `ARCHITECTURE.md`, `CONTRIBUTING.md`, `EXAMPLES.md`) e
  português ao lado (`*.pt-BR.md`). Se mudar um lado, mude o outro — ou
  diga no PR que não deu.

### Commits

Use [Conventional Commits](https://www.conventionalcommits.org/), **em
inglês**:

```
feat: adicionar nova feature
fix: corrigir bug
docs: atualizar documentação
refactor: refatorar código
test: adicionar testes
chore: tarefas de manutenção
```

## Estrutura do Projeto

```
lib/
├── weave_di.dart           # Barrel export
└── src/
    ├── container.dart         # WeaveContainer (interface)
    ├── container_adapter.dart # WeaveContainerAdapter (implementação)
    ├── errors.dart            # os erros que o container lança
    ├── export.dart            # o que o barril reexporta
    ├── gate.dart              # o portão por onde passa a decisão de um guard
    ├── guard.dart             # WeaveGuard
    ├── logger.dart            # WeaveLog
    ├── middleware.dart        # WeaveMiddleware
    ├── module.dart            # WeaveModule
    ├── navigation.dart        # Extensões de BuildContext
    ├── route.dart             # WeaveRoute, WeaveParams
    └── router.dart            # WeaveRouter
```

## Development Setup

### Pré-requisitos

- Flutter SDK >= 3.10.0
- Dart SDK >= 3.12.0

### Rodando

```bash
# Dependências
flutter pub get

# Análise estática
dart analyze

# Testes
flutter test

# Testes com coverage
flutter test --coverage
```

### Estrutura de Testes

A suíte é organizada pela versão que introduziu o comportamento, mais um
arquivo de regressão que impede os bugs já corrigidos de voltarem:

```
test/
├── weave_unit_test.dart            # o container e o router, no nível de unidade
├── weave_2_1_0_test.dart           # guards em onGenerateRoute
├── weave_3_0_0_test.dart           # a superfície da 3.0.0
├── weave_3_0_0_audit_test.dart     # o que a auditoria da 3.0.0 prendeu
├── weave_exports_test.dart         # o barril exporta o que promete
├── weave_inject_factory_test.dart  # injeção tardia numa rota
├── weave_lifecycle_test.dart       # onInit/onDispose de módulo e o grafo
├── weave_nested_routes_test.dart   # a árvore aninhada, o achatamento e breadcrumbs
└── weave_regression_test.dart      # um teste por bug já corrigido
```

## Issues e Bugs

Ao reportar um bug, inclua:

1. Versão do Weave
2. Versão do Flutter
3. Passos pra reproduzir
4. Comportamento esperado vs atual
5. Stack trace se aplicável

## Features Requests

Se você quer uma feature nova, abra uma issue com:

1. Descrição do problema
2. Solução proposta
3. Alternativas consideradas
4. Contexto de uso

## Licença

Ao contribuir, você concorda que suas contribuições serão licenciadas sob a MIT License.
