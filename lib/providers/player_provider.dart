import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;

class PlayerProvider extends ChangeNotifier {
  static final StreamController<String> _externalOpenController = StreamController<String>.broadcast();
  static void openExternalFile(String path) => _externalOpenController.add(path);

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
  
  String _apiKey = '';
  String get apiKey => _apiKey;
  
  final Map<String, String> _translationCache = {};
  String _currentSubtitleText = '';
  String _currentTranslation = '';
  String get currentTranslation => _currentTranslation;

  double _playbackRatio = 16 / 9;
  double get playbackRatio => _playbackRatio;

  BoxFit _videoFit = BoxFit.contain;
  BoxFit get videoFit => _videoFit;

  PlayerProvider({String? initialPath}) {
    _player = Player();
    _controller = VideoController(_player);
    
    // Listen to external file open requests (e.g. from single instance)
    _externalOpenController.stream.listen((path) {
      playFile(path);
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
         _currentSubtitleText = subtitle.first;
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
       notifyListeners();
    });

    // If initial path is provided via command line, play it; otherwise load history
    if (initialPath != null) {
      playFile(initialPath);
    } else {
      _loadHistory();
    }
  }

  void setApiKey(String key) {
    _apiKey = key;
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

  Future<void> openFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video,
    );

    if (result != null && result.files.single.path != null) {
      await playFile(result.files.single.path!);
    }
  }

  Future<void> playFile(String path) async {
    await _loadDirectoryPlaylist(path);
    await _player.open(Media(path));
    _currentFilePath = path;
    _saveHistory(); // Save immediately when a file is opened
    notifyListeners();
  }

  Future<void> _loadDirectoryPlaylist(String filePath) async {
    try {
      final file = File(filePath);
      final directory = file.parent;
      final List<String> mediaExtensions = ['.mp4', '.mkv', '.avi', '.flv', '.mov', '.wmv', '.webm'];
      
      final List<FileSystemEntity> files = directory.listSync();
      _playlist = files
          .where((entity) =>
              entity is File &&
              mediaExtensions.any((ext) => entity.path.toLowerCase().endsWith(ext)))
          .map((entity) => entity.path)
          .toList();
      
      // Sort alphabetically
      _playlist.sort((a, b) => a.compareTo(b));
    } catch (e) {
      debugPrint('Error loading directory playlist: $e');
      _playlist = [filePath];
    }
  }

  Future<void> _playNext() async {
    if (_playlist.isEmpty || _currentFilePath == null) return;
    
    int currentIndex = _playlist.indexOf(_currentFilePath!);
    if (currentIndex != -1 && currentIndex < _playlist.length - 1) {
      final nextPath = _playlist[currentIndex + 1];
      _currentFilePath = nextPath;
      await _player.open(Media(nextPath));
      _saveHistory();
      notifyListeners();
    }
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
    if (!_isAiTranslating || _apiKey.isEmpty || _currentSubtitleText.isEmpty) return;
    
    if (_translationCache.containsKey(_currentSubtitleText)) {
      _currentTranslation = _translationCache[_currentSubtitleText]!;
    } else {
      _currentTranslation = 'AI 正在翻译...';
      notifyListeners();
      
      _currentTranslation = await translateWithGemini(_currentSubtitleText);
      _translationCache[_currentSubtitleText] = _currentTranslation;
    }
    notifyListeners();
  }

  Future<String> translateWithGemini(String text) async {
    try {
      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: _apiKey);
      final content = [Content.text('仅翻译以下视频字幕为简体中文，直接返回结果："$text"')];
      final response = await model.generateContent(content);
      
      return response.text?.trim() ?? '';
    } catch (e) {
      return '翻译连接错误';
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
