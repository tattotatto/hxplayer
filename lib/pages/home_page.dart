import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../providers/player_provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _apiController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _apiController.text = Provider.of<PlayerProvider>(context, listen: false).apiKey;
  }

  @override
  void dispose() {
    _apiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerProvider = Provider.of<PlayerProvider>(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Video(
        controller: playerProvider.controller,
        fit: playerProvider.videoFit,
        controls: (state) => HXControlsOverlay(
          state: state,
          playerProvider: playerProvider,
          apiController: _apiController,
        ),
      ),
    );
  }
}

class HXControlsOverlay extends StatefulWidget {
  final VideoState state;
  final PlayerProvider playerProvider;
  final TextEditingController apiController;

  const HXControlsOverlay({
    super.key,
    required this.state,
    required this.playerProvider,
    required this.apiController,
  });

  @override
  State<HXControlsOverlay> createState() => _HXControlsOverlayState();
}

class _HXControlsOverlayState extends State<HXControlsOverlay> {
  bool _visible = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    if (!mounted) return;
    if (!_visible) setState(() => _visible = true);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      hitTestBehavior: HitTestBehavior.translucent,
      onHover: (_) => _reset(),
      onEnter: (_) => _reset(),
      child: Stack(
        children: [
          // 1. System Controls (Background)
          MaterialVideoControls(widget.state),

          // 2. Custom Header (Title Bar)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            top: _visible ? 0 : -80,
            left: 0,
            right: 0,
            child: _buildHeader(),
          ),

          // 3. Custom Floating Menu
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            bottom: _visible ? 100 : -140, // Floating above system seekbar
            left: 0,
            right: 0,
            child: Center(
              child: _buildControls(context, widget.playerProvider),
            ),
          ),

          // 4. AI Subtitle Overlay
          if (widget.playerProvider.currentTranslation.isNotEmpty)
            Positioned(
              bottom: _visible ? 180 : 80,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.playerProvider.currentTranslation,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF5C6BC0),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return GestureDetector(
      onPanStart: (details) => windowManager.startDragging(),
      onDoubleTap: () async {
        bool isFullScreen = await windowManager.isFullScreen();
        if (!isFullScreen) {
          await windowManager.setFullScreen(true);
          await windowManager.setHasShadow(false);
        } else {
          await windowManager.setFullScreen(false);
        }
      },
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.play_circle_fill, color: Color(0xFF5C6BC0), size: 24),
            const SizedBox(width: 12),
            const Text('HXPLAYER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2, color: Colors.white)),
            const SizedBox(width: 20),
            if (widget.playerProvider.currentFilePath != null)
              Expanded(
                child: Text(
                  widget.playerProvider.currentFilePath!.split(Platform.pathSeparator).last,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const Spacer(),
            IconButton(
              onPressed: () => windowManager.minimize(),
              icon: const Icon(Icons.remove, size: 18, color: Colors.white70),
            ),
            IconButton(
              onPressed: () => windowManager.close(),
              icon: const Icon(Icons.close, size: 18, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context, PlayerProvider provider) {
    return Container(
      width: 780,
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFF161925).withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
             IconButton(
              onPressed: () => provider.resumePlayback(),
              icon: Icon(
                provider.player.state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${_formatDuration(provider.player.state.position)} / ${_formatDuration(provider.player.state.duration)}',
              style: const TextStyle(fontSize: 11, color: Colors.white54, fontFamily: 'monospace'),
            ),
            const Spacer(),
            
            _buildControlBtn(
              icon: Icons.aspect_ratio_rounded,
              label: '比例: ${provider.playbackRatio > 1.7 ? "16:9" : provider.playbackRatio > 1.2 ? "4:3" : "9:16"}',
              onPressed: () {
                 if (provider.playbackRatio > 1.7) provider.setPlaybackRatio(4/3);
                 else if (provider.playbackRatio > 1.2) provider.setPlaybackRatio(9/16);
                 else provider.setPlaybackRatio(16/9);
              },
            ),
            _buildControlBtn(
              icon: Icons.translate_rounded,
              label: 'AI翻译',
              active: provider.isAiTranslating,
              onPressed: provider.toggleAiTranslate,
            ),
            _buildControlBtn(
              icon: Icons.snippet_folder_rounded,
              label: '打开',
              onPressed: provider.openFile,
            ),
            _buildControlBtn(
              icon: provider.videoFit == BoxFit.cover 
                  ? Icons.fullscreen_exit_rounded 
                  : Icons.fit_screen_rounded,
              label: '拉伸',
              active: provider.videoFit == BoxFit.cover,
              onPressed: provider.toggleVideoFit,
            ),
            _buildControlBtn(
              icon: Icons.fullscreen_rounded,
              label: '全屏',
              onPressed: () async {
                bool isFullScreen = await windowManager.isFullScreen();
                if (!isFullScreen) {
                  await windowManager.setFullScreen(true);
                  await windowManager.setHasShadow(false);
                } else {
                  await windowManager.setFullScreen(false);
                }
              },
            ),
            _buildControlBtn(
              icon: Icons.settings_outlined,
              label: '设置',
              onPressed: () => _showSettings(context, provider),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlBtn({required IconData icon, required String label, required VoidCallback onPressed, bool active = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: active ? const Color(0xFF5C6BC0) : Colors.white70,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 10)),
      ),
    );
  }

  void _showSettings(BuildContext context, PlayerProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161925),
        title: const Text('HXPLAYER 配置', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: widget.apiController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Gemini API Key',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF5C6BC0))),
              ),
              onChanged: (val) => provider.setApiKey(val),
            ),
            const SizedBox(height: 12),
            const Text('设置后可开启 AI 实时翻译功能。', style: TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$minutes:$seconds";
  }
}
