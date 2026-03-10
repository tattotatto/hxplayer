import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

import 'pages/home_page.dart';
import 'providers/player_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize MediaKit
  MediaKit.ensureInitialized();
  
  // Initialize WindowManager
  await windowManager.ensureInitialized();
  
  // Single Instance handling
  await WindowsSingleInstance.ensureSingleInstance(
    [], // Arguments to pass to already running instance if needed
    "com.hxplayer.app",
    onSecondWindow: (args) async {
       // This callback runs in the existing instance
       await windowManager.show();
       await windowManager.focus();
    },
  );
  
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    center: true,
    backgroundColor: Colors.black, // Changed from transparent to avoid border bleeding
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'HXPLAYER',
  );
  
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setHasShadow(false); // Remove system shadow which can cause gray lines
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HXPLAYER',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF5C6BC0),
        scaffoldBackgroundColor: const Color(0xFF0F111A),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.dark().textTheme,
        ),
      ),
      home: const HomePage(),
    );
  }
}
