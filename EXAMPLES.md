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
              context.clearStackAndPush(
                context.read<WeaveRouter>(),
                '/',
              );
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

### Estrutura de Módulos

```dart
// auth_module.dart
class AuthModule extends WeaveModule {
  @override
  String get name => 'auth';

  @override
  List<WeaveBind> get binds => [
    (c) => c.bindSingleton<AuthService>(() => AuthServiceImpl()),
    (c) => c.bindSingleton<AuthRepository>(() => AuthRepositoryImpl(
      authService: c.get<AuthService>(),
    )),
  ];

  @override
  List<WeaveRoute> get routes => [
    WeaveRoute(path: '/login', builder: (_, _) => const LoginPage()),
    WeaveRoute(path: '/register', builder: (_, _) => const RegisterPage()),
  ];

  @override
  Future<void> onInit() async {
    // Auto-login se tiver token
    final auth = container.get<AuthService>();
    await auth.tryAutoLogin();
  }
}

// home_module.dart
class HomeModule extends WeaveModule {
  final AuthModule authModule;

  HomeModule({required this.authModule});

  @override
  String get name => 'home';

  @override
  List<WeaveBind> get binds => [
    (c) => c.bind<HomeService>(() => HomeServiceImpl(
      auth: authModule.container.get<AuthService>(),
    )),
  ];

  @override
  List<WeaveRoute> get routes => [
    WeaveRoute(
      path: '/home',
      builder: (_, _) => const HomePage(),
      guards: [WeaveGuard.auth(
        isAuthenticated: (ctx) => ctx.get<AuthService>().isAuthenticated,
      )],
    ),
  ];
}
```

### Registry e Setup

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final registry = WeaveModuleRegistry();
  
  // Registra módulos na ordem de dependência
  registry.register(AuthModule());
  registry.register(HomeModule(
    authModule: registry.get<AuthModule>('auth'),
  ));
  registry.register(FeatureModule(
    authModule: registry.get<AuthModule>('auth'),
  ));

  // Instala todos
  await registry.installAll();

  // Coleta todas as rotas
  final allRoutes = registry.allRoutes;

  runApp(MyApp(routes: allRoutes));

  // Cleanup ao sair
  await registry.disposeAll();
}
```

## 3. Shell Route com Bottom Nav

### Definição

```dart
final appRouter = WeaveRouter(
  routes: [
    WeaveShellRoute(
      path: '/app',
      shellBuilder: (context, child) => Scaffold(
        body: child,
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _getCurrentIndex(context),
          onTap: (index) => _onTap(context, index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.search),
              label: 'Buscar',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: 'Perfil',
            ),
          ],
        ),
      ),
      routes: [
        WeaveRoute(path: '/home', builder: (_, _) => const HomePage()),
        WeaveRoute(path: '/search', builder: (_, _) => const SearchPage()),
        WeaveRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
      ],
    ),
  ],
);
```

### Navegação no Shell

```dart
int _getCurrentIndex(BuildContext context) {
  final path = ModalRoute.of(context)?.settings.name ?? '/';
  switch (path) {
    case '/app/home':
      return 0;
    case '/app/search':
      return 1;
    case '/app/profile':
      return 2;
    default:
      return 0;
  }
}

void _onTap(BuildContext context, int index) {
  final router = context.read<WeaveRouter>();
  final paths = ['/app/home', '/app/search', '/app/profile'];
  context.replaceRoute(router, paths[index]);
}
```

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

## 7. Testing com Override

### Setup de Teste

```dart
testWidgets('login flow', (tester) async {
  // Cria container de teste
  final container = WeaveContainerAdapter(name: 'test');
  
  // Registra mocks
  container.bindSingleton<AuthService>(() => MockAuthService());
  container.bindSingleton<HttpClient>(() => MockHttpClient());
  
  // Override pra teste específico
  container.overrideFactory<AuthService>(() => MockAuthService(
    isAuthenticated: false,
  ));

  // Usa o container nos testes
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Se usando Riverpod
      ],
      child: MyApp(container: container),
    ),
  );

  // Testa o fluxo
  await tester.tap(find.text('Entrar'));
  await tester.pumpAndSettle();
  
  expect(find.byType(HomePage), findsOneWidget);
  
  // Cleanup
  container.reset();
});
```

### Teste de Rotas

```dart
test('route guard blocks unauthenticated user', () async {
  final container = WeaveContainerAdapter(name: 'test');
  container.bindSingleton<AuthService>(() => MockAuthService(
    isAuthenticated: false,
  ));

  final router = WeaveRouter(
    routes: [
      WeaveRoute(
        path: '/protected',
        builder: (_, _) => const ProtectedPage(),
        guards: [WeaveGuard.auth(
          isAuthenticated: (ctx) => ctx.get<AuthService>().isAuthenticated,
          loginPath: '/login',
        )],
      ),
      WeaveRoute(
        path: '/login',
        builder: (_, _) => const LoginPage(),
      ),
    ],
  );

  final match = router.match('/protected');
  expect(match, isNotNull);

  // O guard deve bloquear
  // (teste real precisaria de umBuildContext mockado)
});
```

## 8. Shell Route com Drawer

```dart
WeaveShellRoute(
  path: '/dashboard',
  shellBuilder: (context, child) => Scaffold(
    appBar: AppBar(title: const Text('Dashboard')),
    drawer: Drawer(
      child: ListView(
        children: [
          ListTile(
            title: const Text('Home'),
            onTap: () {
              Navigator.pop(context); // fecha drawer
              context.pushRoute(
                context.read<WeaveRouter>(),
                '/dashboard/home',
              );
            },
          ),
          ListTile(
            title: const Text('Settings'),
            onTap: () {
              Navigator.pop(context);
              context.pushRoute(
                context.read<WeaveRouter>(),
                '/dashboard/settings',
              );
            },
          ),
        ],
      ),
    ),
    body: child,
  ),
  routes: [
    WeaveRoute(path: '/home', builder: (_, _) => const DashboardHome()),
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

## 10. Multi-Navigator com Shell

```dart
WeaveShellRoute(
  path: '/app',
  shellBuilder: (context, child) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          SizedBox(
            width: 250,
            child: NavigationRail(
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
              selectedIndex: _getSelectedIndex(context),
              onDestinationSelected: (index) {
                final paths = ['/app/home', '/app/settings'];
                context.replaceRoute(
                  context.read<WeaveRouter>(),
                  paths[index],
                );
              },
            ),
          ),
          // Conteúdo
          Expanded(child: child),
        ],
      ),
    );
  },
  routes: [
    WeaveRoute(path: '/home', builder: (_, _) => const HomePage()),
    WeaveRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
  ],
);
```
