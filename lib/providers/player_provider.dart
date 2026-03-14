import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class PlayerProvider extends ChangeNotifier {
  static final StreamController<String> _externalOpenController =
      StreamController<String>.broadcast();
  static void openExternalFile(String path) =>
      _externalOpenController.add(path);

  late final Player _player;
  late final VideoController _controller;

  Player get player => _player;
  VideoController get controller => _controller;

  String? _currentFilePath;
  List<String> _playlist = [];

  String? get currentFilePath => _currentFilePath;
  List<String> get playlist => _playlist;

  bool _isAiTranslating = false;
  bool get isAiTranslating => _isAiTranslating;

  String _apiEndpoint =
      'https://dashscope.aliyuncs.com/compatible-mode/v1'; // 默认阿里云作为通用接口
  String _aiModelName = 'qwen-plus';
  String _apiKey = '';

  String get apiEndpoint => _apiEndpoint;
  String get aiModelName => _aiModelName;
  String get apiKey => _apiKey;

  final Map<String, String> _translationCache = {};
  String _currentSubtitleText = '';
  String get currentSubtitleText => _currentSubtitleText;

  String _currentTranslation = '';
  String get currentTranslation => _currentTranslation;

  double _playbackRatio = 1.0;
  double get playbackRatio => _playbackRatio;

  Map<String, dynamic>? _updateInfo;
  Map<String, dynamic>? get updateInfo => _updateInfo;

  BoxFit _videoFit = BoxFit.contain;
  BoxFit get videoFit => _videoFit;

  // 画面微调状态
  double _brightness = 0;
  double _contrast = 0;
  double _saturation = 0;
  double _gamma = 0;
  bool _deband = false;
  double _sharpen = 0;

  double get brightness => _brightness;
  double get contrast => _contrast;
  double get saturation => _saturation;
  double get gamma => _gamma;
  bool get deband => _deband;
  double get sharpen => _sharpen;

  // 视频比例状态
  String _aspectRatioName = '原始比例';
  String get aspectRatioName => _aspectRatioName;

  // 声音/字幕微调
  double _audioDelay = 0;
  double _subDelay = 0;
  double _subPos = 100;

  double get audioDelay => _audioDelay;
  double get subDelay => _subDelay;
  double get subPos => _subPos;

  // 字幕样式微调
  double _subFontSize = 72;
  double _subShadowOffset = 0;
  double _subBorderSize = 2;
  String _subFont = 'sans-serif';

  double get subFontSize => _subFontSize;
  double get subShadowOffset => _subShadowOffset;
  double get subBorderSize => _subBorderSize;
  String get subFont => _subFont;

  SubtitleViewConfiguration get subtitleViewConfiguration =>
      SubtitleViewConfiguration(
        style: TextStyle(
          fontSize: _subFontSize,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          fontFamily: _subFont,
          shadows: [
            if (_subShadowOffset > 0)
              Shadow(
                offset: Offset(_subShadowOffset, _subShadowOffset),
                blurRadius: 2.0,
                color: Colors.black,
              ),
          ],
        ),
        textAlign: TextAlign.center,
        padding: const EdgeInsets.all(24.0),
      );

  Timer? _playTimeoutTimer;
  bool _hasAutoSelectedTracks = false;

  PlayerProvider({String? initialPath}) {
    _player = Player();
    _controller = VideoController(_player);

    // 强制关闭 MPV 的原生字幕显示（通过颜色透明度方案，使其继续抽取文本但不渲染到屏幕）
    _player.stream.playing.listen((isPlaying) {
      if (isPlaying) {
        setMpvProperty('sub-color', '#00000000');
        setMpvProperty('sub-border-color', '#00000000');
        setMpvProperty('sub-shadow-color', '#00000000');
        setMpvProperty('sub-bg-color', '#00000000');
        // 强制移除 ASS 样式，确保透明色生效
        setMpvProperty('sub-ass-override', 'force');
      }
    });

    // 监听底层日志
    _player.stream.log.listen((log) {
      debugPrint('MPV LOG [${log.level}]: ${log.text}');
      if (log.text.contains('demuxer') || log.text.contains('decoder')) {
        debugPrint('--> 关键组件日志: ${log.text}');
      }
    });

    // 监听播放错误
    _player.stream.error.listen((error) {
      debugPrint('！！！播放器错误捕获: $error');
    });

    // Listen to external file open requests (e.g. from single instance)
    _externalOpenController.stream.listen((path) {
      playFile(path);
    });

    _player.stream.tracks.listen((tracks) {
      debugPrint('==== TRACKS UPDATED ====');
      for (var at in tracks.audio)
        debugPrint(
          'AudioTrack: id=${at.id} title=${at.title} lang=${at.language} codec=${at.codec}',
        );
      for (var st in tracks.subtitle)
        debugPrint(
          'SubtitleTrack: id=${st.id} title=${st.title} lang=${st.language} codec=${st.codec}',
        );

      if (!_hasAutoSelectedTracks &&
          (tracks.audio.length > 2 || tracks.subtitle.length > 2)) {
        _autoSelectChineseTracks(tracks);
      }
    });

    // Listen to completion for auto-play next
    _player.stream.completed.listen((completed) {
      if (completed) {
        _playNext();
      }
    });

    // Listen to subtitle changes (Mocked logic for custom subtitle streaming)
    _player.stream.subtitle.listen((subtitle) {
      if (subtitle.isNotEmpty) {
        _currentSubtitleText = subtitle.join('\n');
        _handleSubtitleTranslation();
      } else {
        _currentSubtitleText = '';
        _currentTranslation = '';
        notifyListeners();
      }
    });

    // Listen to position to save history (every 5 seconds)
    _player.stream.position.listen((pos) {
      if (_currentFilePath != null && pos.inSeconds % 5 == 0) {
        _saveHistory();
      }
      notifyListeners(); // Force UI update for seekbars
    });

    _player.stream.playing.listen((isPlaying) {
      if (isPlaying) {
        _playTimeoutTimer?.cancel();
      }
      notifyListeners();
    });

    // If initial path is provided via command line, play it; otherwise load history
    if (initialPath != null) {
      playFile(initialPath);
    } else {
      _loadHistory();
    }

    _loadPreferences();
    checkUpdate();
  }

  Future<void> checkUpdate() async {
    try {
      // 访问我们在网站 public 目录下放置的 version.json
      final response = await http
          .get(Uri.parse('https://hxplayer.hongxikeji.cn/version.json'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final latestVersion = data['latest_version'] as String;
        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version;

        if (_isVersionNewer(latestVersion, currentVersion)) {
          _updateInfo = data;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('检测更新失败: $e');
    }
  }

  void consumeUpdateInfo() {
    _updateInfo = null;
    notifyListeners();
  }

  bool _isVersionNewer(String latest, String current) {
    try {
      final lParts = latest.split('.').map((e) => int.parse(e)).toList();
      final cParts = current.split('.').map((e) => int.parse(e)).toList();
      final length = lParts.length < cParts.length
          ? lParts.length
          : cParts.length;
      for (var i = 0; i < length; i++) {
        if (lParts[i] > cParts[i]) return true;
        if (lParts[i] < cParts[i]) return false;
      }
      return lParts.length > cParts.length;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _apiEndpoint =
        prefs.getString('ai_endpoint') ??
        'https://dashscope.aliyuncs.com/compatible-mode/v1';
    _aiModelName = prefs.getString('ai_model') ?? 'qwen-plus';
    _apiKey = prefs.getString('ai_api_key') ?? '';
  }

  Future<void> saveAiPreferences({
    required String endpoint,
    required String model,
    required String apiKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_endpoint', endpoint);
    await prefs.setString('ai_model', model);
    await prefs.setString('ai_api_key', apiKey);

    _apiEndpoint = endpoint;
    _aiModelName = model;
    _apiKey = apiKey;
    notifyListeners();
  }

  void setPlaybackRatio(double ratio) {
    _playbackRatio = ratio;
    notifyListeners();
  }

  void toggleVideoFit() {
    _videoFit = _videoFit == BoxFit.contain ? BoxFit.cover : BoxFit.contain;
    notifyListeners();
  }

  static const List<String> videoExtensions = [
    'mp4',
    'mkv',
    'avi',
    'flv',
    'mov',
    'wmv',
    'webm',
    'rmvb',
    'rm',
    'ts',
    'vob',
    'm4v',
    '3gp',
    'mpg',
    'mpeg',
  ];

  Future<void> openFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: videoExtensions,
    );

    if (result != null && result.files.single.path != null) {
      await playFile(result.files.single.path!);
    }
  }

  Future<void> playFile(String path) async {
    _playTimeoutTimer?.cancel();
    _hasAutoSelectedTracks = false;

    await _loadDirectoryPlaylist(path);
    await _player.open(Media(path));

    // 针对 RMVB 等潜在不支持格式启动超时检测
    if (path.toLowerCase().endsWith('.rmvb') ||
        path.toLowerCase().endsWith('.rm')) {
      _playTimeoutTimer = Timer(const Duration(seconds: 8), () {
        if (!_player.state.playing && _player.state.position == Duration.zero) {
          debugPrint('RMVB 加载超时，请确认集成解码器是否生效');
        }
      });
    }

    _currentFilePath = path;
    _saveHistory(); // Save immediately when a file is opened
    notifyListeners();

    // 延迟 1.5 秒尝试自动选轨，因为 MPV 加载流信息是异步的
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (_currentFilePath == path) {
        _autoSelectChineseTracks(_player.state.tracks);
      }
    });
  }

  // 播放列表状态查询
  int get currentIndex =>
      _currentFilePath == null ? -1 : _playlist.indexOf(_currentFilePath!);
  bool get hasPrevious => _playlist.isNotEmpty && currentIndex > 0;
  bool get hasNext =>
      _playlist.isNotEmpty &&
      currentIndex != -1 &&
      currentIndex < _playlist.length - 1;

  // 轨道状态查询 (音轨、字幕轨)
  Tracks get tracks => _player.state.tracks;
  AudioTrack get currentAudioTrack => _player.state.track.audio;
  SubtitleTrack get currentSubtitleTrack => _player.state.track.subtitle;

  Future<void> setAudioTrack(AudioTrack track) async {
    await _player.setAudioTrack(track);
    notifyListeners();
  }

  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    await _player.setSubtitleTrack(track);
    notifyListeners();
  }

  Future<void> _loadDirectoryPlaylist(String filePath) async {
    try {
      final file = File(filePath);
      final directory = file.parent;

      final List<FileSystemEntity> files = directory.listSync();
      _playlist = files
          .where(
            (entity) =>
                entity is File &&
                videoExtensions.any(
                  (ext) => entity.path.toLowerCase().endsWith('.$ext'),
                ),
          )
          .map((entity) => entity.path)
          .toList();

      // 自然排序逻辑 (Natural Sort)，处理包含数字的情况，比如 'ep2' 排在 'ep10' 前面
      _playlist.sort((a, b) {
        final regExp = RegExp(r'\d+|\D+');
        final Iterable<Match> matchesA = regExp.allMatches(a.toLowerCase());
        final Iterable<Match> matchesB = regExp.allMatches(b.toLowerCase());

        final Iterator<Match> iterA = matchesA.iterator;
        final Iterator<Match> iterB = matchesB.iterator;

        while (iterA.moveNext() && iterB.moveNext()) {
          final String partA = iterA.current.group(0)!;
          final String partB = iterB.current.group(0)!;

          final int? numA = int.tryParse(partA);
          final int? numB = int.tryParse(partB);

          if (numA != null && numB != null) {
            final result = numA.compareTo(numB);
            if (result != 0) return result;
          } else {
            final result = partA.compareTo(partB);
            if (result != 0) return result;
          }
        }
        return a.length.compareTo(b.length);
      });
    } catch (e) {
      debugPrint('Error loading directory playlist: $e');
      _playlist = [filePath];
    }
  }

  void _autoSelectChineseTracks(Tracks tracks) {
    if (_hasAutoSelectedTracks) return;

    bool autoSelected = false;

    // 移除默认和关闭项
    final realAudio = tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    for (var t in realAudio) {
      if (_isChineseTrackTitleOrLang(t)) {
        debugPrint('自动选中中文音轨: ${t.id} ${t.title}');
        _player.setAudioTrack(t);
        autoSelected = true;
        break;
      }
    }

    // 如果是双语文件但没匹配到标题，尝试默认选第一个（通常是国语）
    if (!autoSelected &&
        realAudio.length >= 2 &&
        (_currentFilePath?.contains('双语') ?? false)) {
      _player.setAudioTrack(realAudio.first);
      autoSelected = true;
    }

    final realSub = tracks.subtitle
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    for (var t in realSub) {
      if (_isChineseTrackTitleOrLang(t)) {
        debugPrint('自动选中中文字幕: ${t.id} ${t.title}');
        _player.setSubtitleTrack(t);
        autoSelected = true;
        break;
      }
    }

    // 兜底设置：如果有超过1个音轨或字幕，标记为已处理，避免重复触发
    if (realAudio.length > 0 || realSub.length > 0) {
      _hasAutoSelectedTracks = true;
    }
  }

  bool _isChineseTrackTitleOrLang(dynamic track) {
    if (track.id == 'auto' || track.id == 'no') return false;
    final title = (track.title ?? '').toLowerCase();
    final lang = (track.language ?? '').toLowerCase();
    final codec = (track.codec ?? '').toLowerCase();
    final combined = '$title $lang $codec';

    // 常见的中文/国粤语关键词匹配
    if (combined.contains('国语') ||
        combined.contains('粤语') ||
        combined.contains('普通话') ||
        combined.contains('mandarin') ||
        combined.contains('cantonese') ||
        combined.contains('中') ||
        combined.contains('简') ||
        combined.contains('繁') ||
        combined.contains('zh') ||
        combined.contains('chi') ||
        combined.contains('zho') ||
        combined.contains('cmn') ||
        combined.contains('yue')) {
      return true;
    }
    return false;
  }

  Future<void> playNext() async {
    if (hasNext) {
      final nextPath = _playlist[currentIndex + 1];
      _currentFilePath = nextPath;
      await _player.open(Media(nextPath));
      _saveHistory();
      notifyListeners();
    }
  }

  Future<void> playPrevious() async {
    if (hasPrevious) {
      final prevPath = _playlist[currentIndex - 1];
      _currentFilePath = prevPath;
      await _player.open(Media(prevPath));
      _saveHistory();
      notifyListeners();
    }
  }

  Future<void> _playNext() async {
    await playNext();
  }

  Future<File> get _historyFile async {
    final directory = await path_provider.getApplicationSupportDirectory();
    return File(p.join(directory.path, 'history.json'));
  }

  Future<void> _saveHistory() async {
    if (_currentFilePath == null) return;
    try {
      final file = await _historyFile;
      final data = {
        'path': _currentFilePath,
        'position': _player.state.position.inMilliseconds,
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('Save history error: $e');
    }
  }

  Future<void> _loadHistory() async {
    try {
      final file = await _historyFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content);
        _currentFilePath = data['path'];
        // Note: We don't open the player yet, just set the path for UI
        if (_currentFilePath != null && File(_currentFilePath!).existsSync()) {
          await _loadDirectoryPlaylist(_currentFilePath!);
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Load history error: $e');
    }
  }

  Future<void> resumePlayback() async {
    if (_player.state.playing) {
      await _player.pause();
    } else if (_currentFilePath != null) {
      if (_player.state.playlist.medias.isEmpty) {
        // Load from history
        final file = await _historyFile;
        int startPos = 0;
        if (await file.exists()) {
          final data = jsonDecode(await file.readAsString());
          startPos = data['position'] ?? 0;
        }
        await _player.open(
          Media(_currentFilePath!, start: Duration(milliseconds: startPos)),
        );
      }
      await _player.play();
    } else {
      await openFile();
    }
    notifyListeners();
  }

  void toggleAiTranslate() {
    _isAiTranslating = !_isAiTranslating;
    if (!_isAiTranslating) {
      _currentTranslation = '';
    } else if (_currentSubtitleText.isNotEmpty) {
      _handleSubtitleTranslation();
    }
    notifyListeners();
  }

  Future<void> _handleSubtitleTranslation() async {
    if (!_isAiTranslating || _apiKey.isEmpty || _currentSubtitleText.isEmpty)
      return;

    if (_translationCache.containsKey(_currentSubtitleText)) {
      _currentTranslation = _translationCache[_currentSubtitleText]!;
    } else {
      _currentTranslation = 'AI 正在翻译...';
      notifyListeners();

      _currentTranslation = await _translateSubtitle(_currentSubtitleText);
      _translationCache[_currentSubtitleText] = _currentTranslation;
    }
    notifyListeners();
  }

  Future<String> _translateSubtitle(String text) async {
    try {
      final String baseUrl = _apiEndpoint.trim().replaceAll(
        RegExp(r'/$'),
        '',
      ); // 移除可能的斜杠
      final Uri url = Uri.parse('$baseUrl/chat/completions');

      final Map<String, dynamic> body = {
        'model': _aiModelName,
        'messages': [
          {
            'role': 'system',
            'content': '你是一名专业的影视字幕翻译。请仅将接下来的外语翻译为流畅的简体中文，不需要任何解释、也不要重复外语部分。',
          },
          {'role': 'user', 'content': text},
        ],
        'temperature': 0.3,
      };

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Bearer $_apiKey',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded['choices'] != null && decoded['choices'].isNotEmpty) {
          final result = decoded['choices'][0]['message']['content']
              .toString()
              .trim();
          return result;
        }
      }
      return '翻译返回格式错误 (${response.statusCode})';
    } catch (e) {
      debugPrint('AI 翻译请求错误：$e');
      return '翻译连接错误或超时';
    }
  }

  // --- 微调功能实现 ---

  Future<void> setMpvProperty(String key, String value) async {
    try {
      await (player.platform as dynamic).setProperty(key, value);
    } catch (e) {
      debugPrint('Set property $key failed: $e');
    }
  }

  // 画面调节
  void updateVideoProperty(String property, double value) {
    if (property == 'brightness') _brightness = value;
    if (property == 'contrast') _contrast = value;
    if (property == 'saturation') _saturation = value;
    if (property == 'gamma') _gamma = value;
    if (property == 'sharpen') _sharpen = value;

    setMpvProperty(property, value.toStringAsFixed(1));
    notifyListeners();
  }

  void toggleDeband() {
    _deband = !_deband;
    setMpvProperty('deband', _deband ? 'yes' : 'no');
    notifyListeners();
  }

  // 比例调节
  void setAspectRatio(String name, String value) {
    _aspectRatioName = name;
    setMpvProperty('video-aspect-override', value);
    notifyListeners();
  }

  // 声音/字幕延迟
  void updateAudioDelay(double seconds) {
    _audioDelay = seconds;
    setMpvProperty('audio-delay', seconds.toStringAsFixed(3));
    notifyListeners();
  }

  void updateSubDelay(double seconds) {
    _subDelay = seconds;
    setMpvProperty('sub-delay', seconds.toStringAsFixed(3));
    notifyListeners();
  }

  void updateSubPos(double pos) {
    _subPos = pos;
    setMpvProperty('sub-pos', pos.toInt().toString());
    notifyListeners();
  }

  // 字幕样式
  void updateSubStyle({
    double? size,
    double? shadow,
    double? border,
    String? font,
  }) {
    if (size != null) {
      _subFontSize = size;
      setMpvProperty('sub-font-size', size.toInt().toString());
    }
    if (shadow != null) {
      _subShadowOffset = shadow;
      setMpvProperty('sub-shadow-offset', shadow.toInt().toString());
    }
    if (border != null) {
      _subBorderSize = border;
      setMpvProperty('sub-border-size', border.toStringAsFixed(1));
    }
    if (font != null) {
      _subFont = font;
      setMpvProperty('sub-font', font);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
