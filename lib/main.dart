import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

import 'pages/home_page.dart';
import 'providers/player_provider.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化 MediaKit
  MediaKit.ensureInitialized();
  
  // 初始化 WindowManager
  await windowManager.ensureInitialized();
  
  // 单实例处理
  await WindowsSingleInstance.ensureSingleInstance(
    args, 
    "com.hxplayer.app",
    onSecondWindow: (newArgs) async {
       await windowManager.show();
       await windowManager.focus();
       if (newArgs.isNotEmpty) {
          PlayerProvider.openExternalFile(newArgs.first);
       }
    },
  );

  String? initialPath = args.isNotEmpty ? args.first : null;
  
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    center: true,
    backgroundColor: Colors.black,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'HXPLAYER',
  );
  
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setHasShadow(false);
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PlayerProvider(initialPath: initialPath)),
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
