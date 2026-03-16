import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
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
    _apiController.text = Provider.of<PlayerProvider>(
      context,
      listen: false,
    ).apiKey;
  }

  @override
  void dispose() {
    _apiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerProvider = Provider.of<PlayerProvider>(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () {
          playerProvider.resumePlayback();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Video(
            controller: playerProvider.controller,
            fit: playerProvider.videoFit,
            // 移除 Flutter 层面的字幕渲染，完全委托给底层的 MPV 引擎
            // 这样可以通过 playerProvider 中的 setMpvProperty('sub-font-size', ...) 完美控制样式、位置乃至 ASS 特效
            subtitleViewConfiguration: const SubtitleViewConfiguration(
              visible: false,
            ),
            controls: (state) => HXControlsOverlay(
              state: state,
              playerProvider: playerProvider,
              apiController: _apiController,
            ),
          ),
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

  // HUD 状态
  String _hudText = '';
  Timer? _hudTimer;

  void _showHUD(String text) {
    if (!mounted) return;
    setState(() => _hudText = text);
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _hudText = '');
    });
  }

  @override
  void initState() {
    super.initState();
    _reset();

    // 监听更新信息
    widget.playerProvider.addListener(_onProviderUpdate);
  }

  void _onProviderUpdate() {
    if (widget.playerProvider.updateInfo != null) {
      final info = widget.playerProvider.updateInfo!;
      widget.playerProvider.consumeUpdateInfo();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showUpdateDialog(info);
      });
    }
  }

  void _showUpdateDialog(Map<String, dynamic> info) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161925),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.system_update_alt, color: Color(0xFF5C6BC0)),
            const SizedBox(width: 8),
            Text(
              '发现新版本 ${info['latest_version']}',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '更新内容:',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              info['release_notes'],
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('以后再说', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5C6BC0),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final url = Uri.parse(info['download_url']);
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('立即下载'),
          ),
        ],
      ),
    );
  }

  void _reset() {
    if (!mounted) return;
    if (!_visible) setState(() => _visible = true);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  Future<void> _toggleFullScreen() async {
    bool isFullScreen = await windowManager.isFullScreen();
    if (!isFullScreen) {
      await windowManager.setFullScreen(true);
      await windowManager.setHasShadow(false);
    } else {
      await windowManager.setFullScreen(false);
    }
  }

  @override
  void dispose() {
    widget.playerProvider.removeListener(_onProviderUpdate);
    _timer?.cancel();
    _hudTimer?.cancel();
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

          // 2. Fullscreen Double-tap Overlay (Visible over native controls)
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (event) {
                if (event.buttons == kSecondaryButton) {
                  _showContextMenu(context, event.position);
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: _toggleFullScreen,
              ),
            ),
          ),

          // HUD Display
          if (_hudText.isNotEmpty)
            Positioned(
              top: 80, // 从屏幕左上侧边缘留白
              left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _hudText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          // 3. Custom Header (Title Bar)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            top: _visible ? 0 : -80,
            left: 0,
            right: 0,
            child: _buildHeader(),
          ),

          // 4. Custom Floating Menu
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            bottom: _visible ? 100 : -140, // Floating above system seekbar
            left: 0,
            right: 0,
            child: Center(
              child: _buildControls(context, widget.playerProvider),
            ),
          ),

          // 4.5 纯手工渲染的可调节字幕层 (替代 mpv 内置和 media_kit_video 锁死的字幕组件)
          if (widget.playerProvider.currentSubtitleText.isNotEmpty)
            Positioned(
              bottom: widget.playerProvider.subPos, // 由 provider 动态管理的位置
              left: 20,
              right: 20,
              child: Center(
                child: Text(
                  widget.playerProvider.currentSubtitleText,
                  textAlign: TextAlign.center,
                  style: widget.playerProvider.subtitleViewConfiguration.style,
                ),
              ),
            ),

          // 5. AI Subtitle Overlay
          if (widget.playerProvider.currentTranslation.isNotEmpty)
            Positioned(
              bottom: _visible ? 180 : 80,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.playerProvider.currentTranslation,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF5C6BC0),
                      fontSize: 72,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          offset: Offset(1.0, 1.0),
                          blurRadius: 3.0,
                          color: Colors.black,
                        ),
                      ],
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
      onDoubleTap: _toggleFullScreen,
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
            const Icon(
              Icons.play_circle_fill,
              color: Color(0xFF5C6BC0),
              size: 24,
            ),
            const SizedBox(width: 12),
            const Text(
              'HXPLAYER',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                letterSpacing: 1.2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 20),
            if (widget.playerProvider.currentFilePath != null)
              Expanded(
                child: Text(
                  widget.playerProvider.currentFilePath!
                      .split(Platform.pathSeparator)
                      .last,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const Spacer(),
            IconButton(
              onPressed: () => widget.playerProvider.toggleAlwaysOnTop(),
              tooltip: widget.playerProvider.isAlwaysOnTop ? '取消置顶' : '置顶显示',
              icon: Icon(
                widget.playerProvider.isAlwaysOnTop
                    ? Icons.push_pin
                    : Icons.push_pin_outlined,
                size: 18,
                color: widget.playerProvider.isAlwaysOnTop
                    ? const Color(0xFF5C6BC0)
                    : Colors.white70,
              ),
            ),
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
            if (provider.hasPrevious)
              IconButton(
                onPressed: () => provider.playPrevious(),
                icon: const Icon(
                  Icons.skip_previous_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            IconButton(
              onPressed: () => provider.resumePlayback(),
              icon: Icon(
                provider.player.state.playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            if (provider.hasNext)
              IconButton(
                onPressed: () => provider.playNext(),
                icon: const Icon(
                  Icons.skip_next_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            const SizedBox(width: 8),
            Text(
              '${_formatDuration(provider.player.state.position)} / ${_formatDuration(provider.player.state.duration)}',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white54,
                fontFamily: 'monospace',
              ),
            ),
            const Spacer(),

            _buildControlBtn(
              icon: Icons.aspect_ratio_rounded,
              label: '比例: ${provider.aspectRatioName}',
              onPressed: () {
                if (provider.playbackRatio > 1.7)
                  provider.setAspectRatio('4:3', '4/3');
                else if (provider.playbackRatio > 1.2)
                  provider.setAspectRatio('9:16', '9/16');
                else
                  provider.setAspectRatio('16:9', '16/9');
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
              onPressed: _toggleFullScreen,
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

  Widget _buildControlBtn({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool active = false,
  }) {
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
    // 预设选项
    final List<Map<String, String>> aiPresets = [
      {
        'name': '阿里云通义千问',
        'endpoint': 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        'model': 'qwen-plus',
      },
      {
        'name': 'DeepSeek',
        'endpoint': 'https://api.deepseek.com/v1',
        'model': 'deepseek-chat',
      },
      {
        'name': 'Moonshot (Kimi)',
        'endpoint': 'https://api.moonshot.cn/v1',
        'model': 'moonshot-v1-8k',
      },
      {'name': '自定义 (OpenAI兼容)', 'endpoint': '', 'model': ''},
    ];

    String currentEndpoint = provider.apiEndpoint;
    String currentModel = provider.aiModelName;
    String currentKey = provider.apiKey;

    // 匹配当前属于哪个 preset
    String currentPresetName = '自定义 (OpenAI兼容)';
    for (var preset in aiPresets) {
      if (preset['endpoint'] == currentEndpoint &&
          preset['name'] != '自定义 (OpenAI兼容)') {
        currentPresetName = preset['name']!;
        break;
      }
    }

    final endpointController = TextEditingController(text: currentEndpoint);
    final modelController = TextEditingController(text: currentModel);
    final keyController = TextEditingController(text: currentKey);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF161925),
            title: const Text(
              'AI 翻译设置',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    dropdownColor: const Color(0xFF1E2233),
                    value: currentPresetName,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: '服务提供商',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF5C6BC0)),
                      ),
                    ),
                    items: aiPresets.map((preset) {
                      return DropdownMenuItem<String>(
                        value: preset['name'],
                        child: Text(preset['name']!),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          currentPresetName = val;
                          if (val != '自定义 (OpenAI兼容)') {
                            final selected = aiPresets.firstWhere(
                              (p) => p['name'] == val,
                            );
                            endpointController.text = selected['endpoint']!;
                            modelController.text = selected['model']!;
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: endpointController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'API Endpoint (Base URL)',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF5C6BC0)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: modelController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Model Name (模型名称)',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF5C6BC0)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: keyController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'API Key (密钥)',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF5C6BC0)),
                      ),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '支持任何兼容 OpenAI /chat/completions 接口的标准模型',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text(
                        '当前版本: 1.0.1',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          await provider.checkUpdate();
                          if (provider.updateInfo == null) {
                            _showHUD('已是最新版本');
                          }
                        },
                        child: const Text(
                          '检查更新',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  '取消',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              TextButton(
                onPressed: () {
                  provider.saveAiPreferences(
                    endpoint: endpointController.text,
                    model: modelController.text,
                    apiKey: keyController.text,
                  );
                  Navigator.pop(ctx);
                  _showHUD('配置已保存');
                },
                child: const Text(
                  '保存',
                  style: TextStyle(
                    color: Color(0xFF5C6BC0),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  OverlayEntry? _contextMenuEntry;

  void _showContextMenu(BuildContext context, Offset position) {
    _closeContextMenu(); // 先关掉上一个

    final provider = context.read<PlayerProvider>();
    _contextMenuEntry = OverlayEntry(
      builder: (context) {
        return Material(
          color: Colors.transparent,
          child: _ContextMenuWidget(
            provider: provider,
            position: position,
            onClose: _closeContextMenu,
            showHUD: _showHUD,
          ),
        );
      },
    );

    Overlay.of(context).insert(_contextMenuEntry!);
  }

  void _closeContextMenu() {
    _contextMenuEntry?.remove();
    _contextMenuEntry = null;
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$minutes:$seconds";
  }
}

// 独立的右键菜单组件，支持内部状态更新与多级折叠
class _ContextMenuWidget extends StatefulWidget {
  final PlayerProvider provider;
  final Offset position;
  final VoidCallback onClose;
  final Function(String) showHUD;

  const _ContextMenuWidget({
    required this.provider,
    required this.position,
    required this.onClose,
    required this.showHUD,
  });

  @override
  State<_ContextMenuWidget> createState() => _ContextMenuWidgetState();
}

class _ContextMenuWidgetState extends State<_ContextMenuWidget> {
  String? _activeSubmenu;
  Offset? _activeSubmenuOffset;

  void _openSubmenu(String title, BuildContext itemContext) {
    final RenderBox renderBox = itemContext.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);

    setState(() {
      if (_activeSubmenu == title) {
        _activeSubmenu = null;
        _activeSubmenuOffset = null;
      } else {
        _activeSubmenu = title;
        _activeSubmenuOffset = Offset(
          position.dx + renderBox.size.width - 4,
          position.dy - 8,
        );
      }
    });
  }

  Widget _buildFontBtn(String label, String font) {
    bool active = widget.provider.subFont == font;
    return TextButton(
      onPressed: () {
        widget.provider.updateSubStyle(font: font);
        widget.showHUD('字体: $label');
      },
      style: TextButton.styleFrom(
        foregroundColor: active ? const Color(0xFF5C6BC0) : Colors.white70,
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }

  void _setRatio(String name, String value) {
    widget.provider.setAspectRatio(name, value);
    widget.showHUD('比例: $name');
    widget.onClose(); // 选择比例后自动关闭
  }

  Widget _buildActionItem(String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ),
    );
  }

  String _getTrackDisplayName(dynamic track, String type) {
    String? title = track.title;
    String? language = track.language;
    String id = track.id;

    if (id == 'no') return '关闭 (Disable)';
    if (id == 'auto') return '默认 (Auto)';

    String langName = language ?? '';
    if (langName.isNotEmpty) {
      final lowered = langName.toLowerCase();
      if (lowered.contains('zh') ||
          lowered.contains('chi') ||
          lowered.contains('zho')) {
        langName = '中文';
      } else if (lowered.contains('en') || lowered.contains('eng')) {
        langName = '英语';
      } else if (lowered.contains('ja') || lowered.contains('jpn')) {
        langName = '日语';
      } else if (lowered.contains('ko') || lowered.contains('kor')) {
        langName = '韩语';
      } else if (lowered.contains('fr') ||
          lowered.contains('fre') ||
          lowered.contains('fra')) {
        langName = '法语';
      } else if (lowered.contains('ru') || lowered.contains('rus')) {
        langName = '俄语';
      } else if (lowered.contains('de') ||
          lowered.contains('ger') ||
          lowered.contains('deu')) {
        langName = '德语';
      }
    }

    String name = '';
    if (title != null && title.isNotEmpty) {
      if (langName.isNotEmpty && !title.contains(langName)) {
        name = '[$langName] $title';
      } else {
        name = title;
      }
    } else if (langName.isNotEmpty) {
      name = langName;
    } else {
      String displayId = id.contains('/') ? id.split('/').last : id;
      name = (type == 'audio' ? '音轨 ' : '字幕 ') + displayId;
    }

    String extraInfo = '';
    try {
      String? codec = track.codec;
      String? channels = track.channels;
      if (codec != null && codec.isNotEmpty) {
        extraInfo += codec.toUpperCase();
      }
      if (channels != null && channels.isNotEmpty) {
        if (extraInfo.isNotEmpty) extraInfo += ' ';
        String ch = channels.toUpperCase();
        if (RegExp(r'^\d+(\.\d+)?$').hasMatch(ch)) {
          ch += 'CH';
        }
        extraInfo += ch;
      }
    } catch (_) {}

    if (extraInfo.isNotEmpty) {
      return '$name ($extraInfo)';
    }

    return name;
  }

  List<Widget>? _getSubmenuChildren(String title) {
    if (title == '选集') {
      final playlist = widget.provider.playlist;
      final currentIndex = widget.provider.currentIndex;
      if (playlist.isEmpty) return null;

      int halfWindow = 5;
      int start = currentIndex - halfWindow;
      int end = currentIndex + halfWindow;

      if (start < 0) {
        end += -start;
        start = 0;
      }
      if (end >= playlist.length) {
        start -= (end - playlist.length + 1);
        end = playlist.length - 1;
      }

      start = start.clamp(0, playlist.length - 1);
      end = end.clamp(0, playlist.length - 1);

      List<Widget> items = [];
      if (start > 0) {
        items.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Center(
              child: Text('↑ 前面还有 $start 集',
                  style: const TextStyle(color: Colors.white38, fontSize: 11))),
        ));
      }

      for (int i = start; i <= end; i++) {
        final path = playlist[i];
        final fileName = path.split(RegExp(r'[\\/]')).last;
        final isCurrent = i == currentIndex;
        items.add(InkWell(
          onTap: () {
            if (!isCurrent) {
              widget.provider.playFile(path);
              widget.onClose();
            }
          },
          child: Container(
            color: isCurrent ? Colors.white12 : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    fileName,
                    style: TextStyle(
                      color: isCurrent ? const Color(0xFF8C9EFF) : Colors.white70,
                      fontSize: 13,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isCurrent) const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.play_arrow_rounded, color: Color(0xFF8C9EFF), size: 14),
                    ),
              ],
            ),
          ),
        ));
      }

      if (end < playlist.length - 1) {
        final remaining = playlist.length - 1 - end;
        items.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Center(
              child: Text('↓ 后面还有 $remaining 集',
                  style: const TextStyle(color: Colors.white38, fontSize: 11))),
        ));
      }
      return items;
    } else if (title == '选择字幕') {
      List<Widget> items = [];
      final tracks = widget.provider.tracks.subtitle;
      final current = widget.provider.currentSubtitleTrack;
      if (tracks.isEmpty) {
        items.add(const Padding(
            padding: EdgeInsets.all(16),
            child: Text('无可用字幕', style: TextStyle(color: Colors.white54, fontSize: 12))));
      } else {
        for (var track in tracks) {
          final isSelected = track == current;
          final String label = _getTrackDisplayName(track, 'subtitle');
          items.add(_buildActionItem('${isSelected ? "✓ " : ""}$label', () {
            widget.provider.setSubtitleTrack(track);
            widget.showHUD('已切换字幕: $label');
            widget.onClose();
          }));
        }
      }
      return items;
    } else if (title == '选择音轨') {
      List<Widget> items = [];
      final tracks = widget.provider.tracks.audio;
      final current = widget.provider.currentAudioTrack;
      if (tracks.isEmpty) {
        items.add(const Padding(
            padding: EdgeInsets.all(16),
            child: Text('无可用音轨', style: TextStyle(color: Colors.white54, fontSize: 12))));
      } else {
        for (var track in tracks) {
          final isSelected = track == current;
          final String label = _getTrackDisplayName(track, 'audio');
          items.add(_buildActionItem('${isSelected ? "✓ " : ""}$label', () {
            widget.provider.setAudioTrack(track);
            widget.showHUD('已切换音轨: $label');
            widget.onClose();
          }));
        }
      }
      return items;
    } else if (title == '视频画面') {
      return [
        _CustomSliderItem(
            label: '亮度',
            value: widget.provider.brightness,
            min: -100,
            max: 100,
            step: 1,
            onChanged: (v) {
              widget.provider.updateVideoProperty('brightness', v);
              widget.showHUD('亮度: ${v.toInt()}');
              setState(() {});
            }),
        _CustomSliderItem(
            label: '对比度',
            value: widget.provider.contrast,
            min: -100,
            max: 100,
            step: 1,
            onChanged: (v) {
              widget.provider.updateVideoProperty('contrast', v);
              widget.showHUD('对比度: ${v.toInt()}');
              setState(() {});
            }),
        _buildActionItem('去色带: ${widget.provider.deband ? "开启" : "关闭"}', () {
          widget.provider.toggleDeband();
          widget.showHUD('去色带: ${widget.provider.deband ? "开启" : "关闭"}');
          setState(() {});
        }),
      ];
    } else if (title == '画面比例') {
      return [
        _buildActionItem('原始比例', () => _setRatio('原始比例', '-1')),
        _buildActionItem('16:9', () => _setRatio('16:9', '16/9')),
        _buildActionItem('4:3', () => _setRatio('4:3', '4/3')),
        _buildActionItem('9:16 (手机)', () => _setRatio('9:16', '9/16')),
        _buildActionItem('2.35:1', () => _setRatio('2.35:1', '2.35')),
      ];
    } else if (title == '声音与字幕') {
      return [
        _CustomSliderItem(
            label: '音频延迟',
            value: widget.provider.audioDelay,
            min: -10,
            max: 10,
            step: 0.1,
            onChanged: (v) {
              widget.provider.updateAudioDelay(v);
              widget.showHUD('音频延迟: ${v.toStringAsFixed(1)}s');
              setState(() {});
            }),
        _CustomSliderItem(
            label: '字幕大小',
            value: widget.provider.subFontSize,
            min: 20,
            max: 150,
            step: 2,
            onChanged: (v) {
              widget.provider.updateSubStyle(size: v);
              widget.showHUD('字幕大小: ${v.toInt()}');
              setState(() {});
            }),
        _CustomSliderItem(
            label: '字幕位置',
            value: widget.provider.subPos,
            min: 0,
            max: 150,
            step: 5,
            onChanged: (v) {
              widget.provider.updateSubPos(v);
              widget.showHUD('字幕位置: ${v.toInt()}');
              setState(() {});
            }),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Text('字体: ', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const Spacer(),
              _buildFontBtn('黑体', 'sans-serif'),
              _buildFontBtn('宋体', 'serif'),
              _buildFontBtn('等宽', 'monospace'),
            ],
          ),
        ),
      ];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 阻断底层点击并用于关闭菜单的透明背景板
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onClose,
            onSecondaryTapDown: (_) => widget.onClose(),
          ),
        ),
        // 主菜单
        Positioned(
          left: widget.position.dx,
          top: widget.position.dy,
          child: Container(
            width: 220,
            decoration: BoxDecoration(
              color: const Color(0xFF161925),
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.provider.playlist.isNotEmpty) _buildParentItem('选集'),
                _buildParentItem('选择字幕'),
                _buildParentItem('选择音轨'),
                _buildParentItem('视频画面'),
                _buildParentItem('画面比例'),
                _buildParentItem('声音与字幕'),
                const Divider(color: Colors.white10, height: 1),
                _buildActionItem('关于我们', () {
                  widget.onClose();
                  _showAboutDialog(context);
                }),
              ],
            ),
          ),
        ),
        // 二级菜单（作为 Stack 的直接子元素，彻底避免 HitTest 穿透）
        if (_activeSubmenu != null &&
            _activeSubmenuOffset != null &&
            _getSubmenuChildren(_activeSubmenu!) != null)
          Positioned(
            left: _activeSubmenuOffset!.dx,
            top: _activeSubmenuOffset!.dy,
            child: Container(
              width: 240,
              decoration: BoxDecoration(
                color: const Color(0xFF1E2233), // 更深的颜色区分
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 10,
                    offset: Offset(4, 4),
                  ),
                ],
                border: Border.all(color: Colors.white12),
              ),
              child: Material(
                color: Colors.transparent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _getSubmenuChildren(_activeSubmenu!)!,
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showAboutDialog(BuildContext context) {
    const String appName = 'HXPLAYER';
    const String version = '1.0.0';
    const String date = '2026-03-15 (user setup)';
    const String flutterVer = '3.24.1';
    const String mediaKitVer = '1.1.11';
    const String engineVer = 'MPV 0.38.0';

    final String infoText = '''版本: $version
日期: $date
Flutter: $flutterVer
MediaKit: $mediaKitVer
Engine: $engineVer
OS: Windows 10/11 x64''';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF10141D),
        contentPadding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        content: SizedBox(
          width: 400,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF00ACC1), width: 2.5),
                ),
                child: const Icon(Icons.info_outline,
                    color: Color(0xFF00ACC1), size: 32),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      appName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w400,
                        fontFamily: 'Segoe UI',
                      ),
                    ),
                    const SizedBox(height: 20),
                    ...infoText.split('\n').map((line) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            line,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12.5,
                              fontFamily: 'Consolas',
                            ),
                          ),
                        )),
                    const SizedBox(height: 16),
                    const Text(
                      '云南宏曦科技有限公司荣誉出品',
                      style: TextStyle(
                        color: Colors.white24,
                        fontSize: 11,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, right: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: infoText));
                    widget.showHUD('已复制技术信息');
                    Navigator.pop(ctx);
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF323B54),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(2)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text('复制',
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF323B54),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(2)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text('确定',
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParentItem(String title) {
    bool isExpanded = _activeSubmenu == title;

    return Builder(
      builder: (itemContext) {
        return InkWell(
          onTap: () => _openSubmenu(title, itemContext),
          child: Container(
            color: isExpanded ? Colors.white12 : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                const Spacer(),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_right_rounded,
                  color: Colors.white70,
                  size: 18,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CustomSliderItem extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final Function(double) onChanged;

  const _CustomSliderItem({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            '$label: ${value.toStringAsFixed(step < 1 ? 1 : 0)}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const Spacer(),
          _Btn(
            icon: Icons.remove,
            onTap: () {
              if (value - step >= min) onChanged(value - step);
            },
          ),
          const SizedBox(width: 8),
          _Btn(
            icon: Icons.add,
            onTap: () {
              if (value + step <= max) onChanged(value + step);
            },
          ),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _Btn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, color: Colors.white, size: 14),
      ),
    );
  }
}
