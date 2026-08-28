# Contribuindo pro Weave

Obrigado por querer contribuir! Esse documento explica como participar.

## Como Contribuir

### 1. Fork o Repositório

```bash
git clone https://github.com/seu-usuario/weave.git
cd weave
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
- Testes de unidade优先
- Testes de widget quando necessário
- Não teste implementação, teste comportamento

### Documentação

- Toda feature pública precisa de dartdoc
- README deve ser atualizado se mudar API pública
- CHANGELOG deve ser atualizado pra cada release

### Commits

Use [Conventional Commits](https://www.conventionalcommits.org/pt-BR/v1.0.0/):

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
├── weave.dart              # Barrel export
└── src/
    ├── binding.dart        # WeaveBinding
    ├── container.dart      # WeaveContainer (interface)
    ├── container_adapter.dart # WeaveContainerAdapter (impl)
    ├── guard.dart          # WeaveGuard
    ├── middleware.dart      # WeaveMiddleware
    ├── module.dart         # WeaveModule
    ├── navigation.dart     # Extensões de BuildContext
    ├── route.dart          # WeaveRoute, WeaveParams
    ├── router.dart         # WeaveRouter
    └── shell_route.dart    # WeaveShellRoute
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

```
test/
├── weave_unit_test.dart    # Testes unitários
└── weave_widget_test.dart  # Testes de widget (futuro)
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
