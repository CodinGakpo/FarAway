import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'screens/auth/login_screen.dart';
import 'screens/customer_home_screen.dart';
import 'screens/driver_home_screen.dart';
import 'services/auth_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- dotenv ---
  try {
    await dotenv.load(fileName: '.env');
    debugPrint('[startup] dotenv loaded — BASE_URL=${dotenv.env['BASE_URL']}');
  } catch (e) {
    // App can still launch; API calls will fail until .env is populated.
    debugPrint('[startup] dotenv load failed: $e');
  }

  // --- Firebase ---
  // google-services.json (Android) and GoogleService-Info.plist (iOS) must be
  // present for this to succeed. Until they are added the app still starts but
  // Firebase features will be unavailable.
  try {
    await Firebase.initializeApp();
    debugPrint('[startup] Firebase initialised');
  } catch (e) {
    debugPrint('[startup] Firebase init failed (config files missing?): $e');
  }

  debugPrint('[startup] calling runApp');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(),
        ),
      ],
      child: MaterialApp(
        title: 'Freight Bridge',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1D9E75)),
          primaryColor: const Color(0xFF1D9E75),
          fontFamily: 'sans-serif',
          useMaterial3: true,
        ),
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _isCheckingAuth = true;

  @override
  void initState() {
    super.initState();
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    debugPrint('[_AuthGate] tryAutoLogin — start');
    final authProvider = context.read<AuthProvider>();

    // Guard against a hung keychain read on first-boot / locked device.
    await authProvider.tryAutoLogin().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        debugPrint('[_AuthGate] tryAutoLogin timed out — proceeding as logged out');
      },
    );

    debugPrint('[_AuthGate] tryAutoLogin — done; isLoggedIn=${authProvider.isLoggedIn}');

    if (!mounted) {
      return;
    }
    setState(() {
      _isCheckingAuth = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        if (_isCheckingAuth) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!authProvider.isLoggedIn) {
          return const LoginScreen();
        }

        if (authProvider.isDriver) {
          return const DriverHomeScreen();
        }

        return const CustomerHomeScreen();
      },
    );
  }
}
