import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assa/firebase_options.dart';
import 'package:assa/core/theme/app_theme.dart';
import 'package:assa/screens/splash/splash_screen.dart';
import 'package:assa/services/notification_service.dart';
import 'package:assa/services/theme_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Load persisted theme choice before first frame so there's no flash
  // of the wrong theme on launch.
  await ThemeController.instance.init();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    // Initialize push notifications in background — do NOT await
    // getToken() requires internet and will hang the app if data is off
    NotificationService.instance.initialize().catchError((_) {});
  } catch (e) {
    debugPrint('Firebase init error: \$e');
  }

  runApp(const AssaApp());
}

class AssaApp extends StatelessWidget {
  const AssaApp({super.key});

  @override
  Widget build(BuildContext context) {
    // FIX: wrapped MaterialApp in an AnimatedBuilder listening to
    // ThemeController so Theme screen changes apply instantly app-wide.
    // AppTheme.lightTheme stays the default light theme exactly as
    // before; darkTheme/themeMode are additive only.
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'ASSA',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeController.instance.themeMode,
          builder: (context, child) {
            final scale = ThemeController.instance.textScaleFactor;
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
              ),
              child: child!,
            );
          },
          home: const SplashScreen(),
        );
      },
    );
  }
}