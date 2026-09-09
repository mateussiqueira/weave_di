**Português** · [English](EXAMPLES.md)

# Exemplos do Weave

Exemplos práticos de como usar o Weave em projetos reais.

## 1. App com Autenticação

### Setup do Container

```dart
import 'package:weave_di/weave_di.dart';

void setupDI() {
  final c = WeaveContainerAdapter.global;

  // Core
  c.bindSingleton<HttpClient>(() => DioHttpClient());
  c.bindSingleton<StorageService>(() => SharedPreferencesStorage());

  // Auth
  c.bindSingleton<AuthService>(() => AuthServiceImpl(
    httpClient: c.get<HttpClient>(),
    storage: c.get<StorageService>(),
  ));
  c.bindSingleton<UserRepository>(() => UserRepositoryImpl(
    httpClient: c.get<HttpClient>(),
  ));

  // Features
  c.bindLazy<HomeService>(() => HomeServiceImpl(
    auth: c.get<AuthService>(),
  ));
}
```

### Rotas com Auth Guard

```dart
final authGuard = WeaveGuard.auth(
  isAuthenticated: (context) => context.get<AuthService>().isAuthenticated,
  loginPath: '/login',
);

final appRouter = WeaveRouter(
  middlewares: [
    WeaveMiddleware.log(),
  ],
  routes: [
    WeaveRoute(
      path: '/login',
      name: 'login',
      skipGuards: true,
      builder: (context, params) => const LoginPage(),
    ),
    WeaveRoute(
      path: '/',
      name: 'home',
      builder: (context, params) => const HomePage(),
      guards: [authGuard],
    ),
    WeaveRoute(
      path: '/profile/:id',
      name: 'profile',
      builder: (context, params) => ProfilePage(
        userId: params.getInt('id'),
      ),
      guards: [authGuard],
      transition: WeaveTransition.slideRight,
    ),
  ],
);
```

`skipGuards: true` no `/login` importa: sem ele, um guard global embrulha a
própria página de login e o redirect vira laço.

### Login Page

```dart
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final auth = context.get<AuthService>();
            await auth.login(email: '...', password: '...');
            
            if (context.mounted) {
              context.clearStackAndPush(appRouter, '/');
            }
          },
          child: const Text('Entrar'),
        ),
      ),
    );
  }
}
```

## 2. App Modular

`name`, `binds`, `routes` e `imports` são **campos do construtor**, não getters
sobrescrevíveis. Um módulo que depende de outro o declara em `imports`, e o
`installAll` resolve a ordem topologicamente — então a ordem de registro não
importa, e um módulo importado por dois é instalado uma vez só.

```dart
// auth_module.dart
class AuthModule extends WeaveModule {
  AuthModule()
      : super(
          name: 'auth',
          binds: [
            (c) => c.bindSingleton<AuthService>(() => AuthServiceImpl()),
            (c) => c.bindSingleton<AuthRepository>(
                  () => AuthRepositoryImpl(authService: c.get<AuthService>()),
                ),
          ],
          routes: [
            WeaveRoute(
              path: '/login',
              skipGuards: true,
              builder: (_, _) => const LoginPage(),
            ),
            WeaveRoute(path: '/register', builder: (_, _) => const RegisterPage()),
          ],
        );

  @override
  Future<void> onInit() async {
    // Auto-login quando já existe token guardado
    await container.get<AuthService>().tryAutoLogin();
  }
}

// home_module.dart
class HomeModule extends WeaveModule {
  HomeModule(AuthModule auth)
      : super(
          name: 'home',
          imports: [auth],
          binds: [
            (c) => c.bind<HomeService>(
                  () => HomeServiceImpl(auth: c.get<AuthService>()),
                ),
          ],
          routes: [
            WeaveRoute(
              path: '/home',
              builder: (_, _) => const HomePage(),
              guards: [
                WeaveGuard.auth(
                  isAuthenticated: (ctx) =>
                      ctx.get<AuthService>().isAuthenticated,
                ),
              ],
            ),
          ],
        );
}
```

Como o `HomeModule` importa o `AuthModule`, o container dele resolve
`AuthService` subindo — não precisa alcançar o container do outro módulo à mão.

### Registry e setup

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final auth = AuthModule();
  final registry = WeaveModuleRegistry()
    ..register(auth)
    ..register(HomeModule(auth));

  await registry.installAll();

  final root = registry.get<HomeModule>('home');
  runApp(MyApp(
    router: WeaveRouter(
      routes: root.allRoutes,
      container: root.container,
    ),
  ));
}
```

O `allRoutes` é **do módulo**, e inclui as rotas de tudo que ele importa. O
registry expõe `register`, `get<T>(name)`, `installAll` e `disposeAll`.

## 3. Bottom nav que permanece

Não existe tipo de shell route. Um layout que permanece enquanto o conteúdo
muda é o `layoutBuilder` numa rota aninhada: ele envolve a rota e toda a
subárvore dela, e é composição de widget, não Navigator aninhado — a pilha
continua sendo uma só, e o layout é reconstruído a cada rota.

```dart
final appRouter = WeaveRouter(
  routes: [
    WeaveRoute(
      path: '/app',
      name: 'app',
      layoutBuilder: (context, child) => Scaffold(
        body: child,
        bottomNavigationBar: _AppNav(router: appRouter),
      ),
      builder: (_, _) => const HomePage(),
      children: [
        WeaveRoute(path: '/search', builder: (_, _) => const SearchPage()),
        WeaveRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
      ],
    ),
  ],
);
// vira /app, /app/search, /app/profile — os três dentro do mesmo layout
```

A aba atual sai da rota que o Navigator está mostrando:

```dart
class _AppNav extends StatelessWidget {
  const _AppNav({required this.router});

  final WeaveRouter router;

  static const List<String> _paths = <String>[
    '/app',
    '/app/search',
    '/app/profile',
  ];

  @override
  Widget build(BuildContext context) {
    final String path = ModalRoute.of(context)?.settings.name ?? '/app';
    final int index = _paths.indexOf(path);

    return BottomNavigationBar(
      currentIndex: index < 0 ? 0 : index,
      onTap: (int i) => context.replaceRoute(router, _paths[i]),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Buscar'),
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Perfil'),
      ],
    );
  }
}
```

O `-1` do `indexOf` é tratado: um caminho fora da lista estouraria dentro do
`build`, e uma barra de navegação que quebra leva a tela inteira com ela.

## 4. Factory com Parâmetros

### Registro

```dart
final c = WeaveContainerAdapter.global;

// Factory que precisa de Database
c.bindFactory<UserRepository, Database>(
  (db) => UserRepositoryImpl(database: db),
);

// Factory que precisa de 2 coisas
c.bindFactory2<ProfileService, AuthService, UserRepository>(
  (auth, repo) => ProfileServiceImpl(auth: auth, repo: repo),
);

// Factory que precisa de 3 coisas
c.bindFactory3<NotificationService, AuthService, Database, Config>(
  (auth, db, config) => NotificationServiceImpl(
    auth: auth,
    database: db,
    config: config,
  ),
);
```

### Uso

```dart
// Resolve com dependências
final db = c.get<Database>();
final userRepo = c.get1<UserRepository, Database>(db);

final auth = c.get<AuthService>();
final userRepo = c.get<UserRepository>(); // se já registrado como singleton
final profileService = c.get2<ProfileService, AuthService, UserRepository>(
  auth,
  userRepo,
);
```

## 5. Middleware de Analytics

### Implementação

```dart
class AnalyticsMiddleware implements WeaveMiddleware {
  final AnalyticsService analytics;

  AnalyticsMiddleware({required this.analytics});

  @override
  Future<bool> onNavigate(
    BuildContext context,
    String path,
    WeaveParams params,
  ) async {
    // Rastreia navegação
    analytics.trackEvent('navigation', {
      'path': path,
      'params': params.raw,
    });
    return true; // sempre permite
  }

  @override
  void onRouteMatched(BuildContext context, WeaveRouteMatch match) {
    // Rastreia quando a rota é encontrada
    analytics.trackScreenView(match.route.name ?? match.route.path);
  }
}
```

### Uso

```dart
final router = WeaveRouter(
  middlewares: [
    AnalyticsMiddleware(analytics: getIt<AnalyticsService>()),
    WeaveMiddleware.log(),
  ],
  routes: [...],
);
```

## 6. Redirect Condicional

### Exemplo: Redirecionar se já logado

```dart
WeaveRoute(
  path: '/login',
  redirect: (context, params) {
    final auth = context.get<AuthService>();
    if (auth.isAuthenticated) {
      return '/home'; // já logado, vai pra home
    }
    return null; // mostra login
  },
  builder: (context, params) => const LoginPage(),
);
```

### Exemplo: Feature Flag

```dart
WeaveRoute(
  path: '/beta-feature',
  redirect: (context, params) {
    final config = context.get<ConfigService>();
    if (!config.isBetaEnabled) {
      return '/home'; // feature desabilitada
    }
    return null;
  },
  builder: (context, params) => const BetaFeaturePage(),
);
```

## 7. Testando com override

### Setup de teste

```dart
testWidgets('o fluxo de login chega na home', (tester) async {
  final container = WeaveContainerAdapter(name: 'test');

  container.bindSingleton<AuthService>(() => MockAuthService());
  container.bindSingleton<HttpClient>(() => MockHttpClient());

  // Override para um teste específico
  container.overrideFactory<AuthService>(
    () => MockAuthService(isAuthenticated: false),
  );

  await tester.pumpWidget(MyApp(container: container));

  await tester.tap(find.text('Entrar'));
  await tester.pumpAndSettle();

  expect(find.byType(HomePage), findsOneWidget);

  container.reset();
});
```

Sem `ProviderScope` e sem um segundo injetor: o Weave é DI mais rotas, e o
container é o único. O exemplo envolvia o widget no escopo de outro injetor, o
que ensinava o contrário do que este pacote existe para fazer.

### Testando uma rota

```dart
test('o router casa a rota protegida', () {
  final router = WeaveRouter(
    routes: [
      WeaveRoute(
        path: '/protected',
        builder: (_, _) => const ProtectedPage(),
        guards: [
          WeaveGuard.auth(
            isAuthenticated: (ctx) => ctx.get<AuthService>().isAuthenticated,
            loginPath: '/login',
          ),
        ],
      ),
      WeaveRoute(
        path: '/login',
        skipGuards: true,
        builder: (_, _) => const LoginPage(),
      ),
    ],
  );

  expect(router.match('/protected'), isNotNull);
});
```

Casar e guardar são perguntas diferentes: o `match` responde se o caminho
resolve para uma rota, e o guard roda com um `BuildContext` de verdade. Para
provar que o guard **bloqueia**, dirija-o por um teste de widget com
`pumpWidget` e o `routeFactory` do router — que é o que
`test/weave_2_1_0_test.dart` faz.

## 8. Drawer que permanece

Mesmo mecanismo do bottom nav: `layoutBuilder` na rota pai.

```dart
WeaveRoute(
  path: '/dashboard',
  layoutBuilder: (context, child) => Scaffold(
    appBar: AppBar(title: const Text('Dashboard')),
    drawer: Drawer(
      child: ListView(
        children: [
          ListTile(
            title: const Text('Home'),
            onTap: () {
              Navigator.pop(context); // fecha o drawer
              context.replaceRoute(appRouter, '/dashboard');
            },
          ),
          ListTile(
            title: const Text('Settings'),
            onTap: () {
              Navigator.pop(context);
              context.replaceRoute(appRouter, '/dashboard/settings');
            },
          ),
        ],
      ),
    ),
    body: child,
  ),
  builder: (_, _) => const DashboardHome(),
  children: [
    WeaveRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
  ],
);
```

## 9. Transição Customizada

```dart
class CustomTransition extends WeaveTransition {
  const CustomTransition()
      : super(
          type: WeaveTransitionType.fade,
          duration: Duration(milliseconds: 500),
          curve: Curves.bounceIn,
        );
}

// Uso
WeaveRoute(
  path: '/animated',
  transition: const CustomTransition(),
  builder: (context, params) => const AnimatedPage(),
);
```

Ou com builder customizado:

```dart
WeaveRoute(
  path: '/custom',
  transition: WeaveTransition(
    type: WeaveTransitionType.none, // desabilita o built-in
    customBuilder: (animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1.0, 0.5),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.elasticOut,
        )),
        child: child,
      );
    },
  ),
  builder: (context, params) => const CustomPage(),
);
```

## 10. Sidebar numa tela larga

A versão desktop e web da mesma ideia. Nada aqui precisa de um segundo
Navigator: a sidebar é parte do layout, e o conteúdo é o filho.

```dart
WeaveRoute(
  path: '/app',
  layoutBuilder: (context, child) {
    const List<String> paths = <String>['/app', '/app/settings'];
    final String current = ModalRoute.of(context)?.settings.name ?? '/app';
    final int index = paths.indexOf(current);

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index < 0 ? 0 : index,
            onDestinationSelected: (int i) =>
                context.replaceRoute(appRouter, paths[i]),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.home),
                label: Text('Home'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          Expanded(child: child),
        ],
      ),
    );
  },
  builder: (_, _) => const HomePage(),
  children: [
    WeaveRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
  ],
);
```

## 11. Deep link que monta a pilha inteira

Entrar em `/cadernos/7/gabarito` — por URL, por push notification, ou pelo
botão voltar do browser — normalmente cria uma rota só, e o voltar fecha o
app.

```dart
WeaveRouter(
  routes: routes,
  stackAncestorsOnDeepLink: true,
);
// /cadernos/7/gabarito  ->  [/cadernos, /cadernos/7, /cadernos/7/gabarito]
```

Segmento sem rota registrada é pulado, não vira 404, e a query fica só na
folha. Use junto com `onGenerateInitialRoutes: router.onGenerateInitialRoutes`
no `MaterialApp`, senão o Flutter quebra o caminho ele mesmo e empilha três
páginas sem relação.
