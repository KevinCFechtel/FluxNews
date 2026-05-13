import 'dart:async';

import 'package:flutter/services.dart';

class DynamicIslandService {
  static const platform = MethodChannel('dev.kevincfechtel.fluxnews/dynamicisland');

  static String? _currentActivityId;
  late final StreamController<void> _playPauseController;
  late final StreamController<void> _skipForwardController;

  DynamicIslandService() {
    _playPauseController = StreamController<void>.broadcast();
    _skipForwardController = StreamController<void>.broadcast();
    _setupNotificationListeners();
  }

  void _setupNotificationListeners() {
    platform.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPlayPause':
          _playPauseController.add(null);
          break;
        case 'onSkipForward':
          _skipForwardController.add(null);
          break;
      }
    });
  }

  /// Start a new Dynamic Island activity
  Future<String?> startActivity({
    required String itemTitle,
    required String feedTitle,
    required bool isPlaying,
    required int currentPosition,
    required int duration,
    String? artworkUrl,
  }) async {
    try {
      final activityId = await platform.invokeMethod<String>(
        'startActivity',
        {
          'itemTitle': itemTitle,
          'feedTitle': feedTitle,
          'isPlaying': isPlaying,
          'currentPosition': currentPosition,
          'duration': duration,
          'artworkUrl': artworkUrl,
          'activityId': _currentActivityId ?? '',
        },
      );
      _currentActivityId = activityId;
      return activityId;
    } catch (e) {
      // Silently ignore for non-iOS platforms or older iOS versions
      return null;
    }
  }

  /// Update the current Dynamic Island activity
  Future<void> updateActivity({
    required String itemTitle,
    required String feedTitle,
    required bool isPlaying,
    required int currentPosition,
    required int duration,
    String? artworkUrl,
  }) async {
    try {
      await platform.invokeMethod(
        'updateActivity',
        {
          'itemTitle': itemTitle,
          'feedTitle': feedTitle,
          'isPlaying': isPlaying,
          'currentPosition': currentPosition,
          'duration': duration,
          'artworkUrl': artworkUrl,
        },
      );
    } catch (e) {
      // Silently ignore for non-iOS platforms or older iOS versions
    }
  }

  /// End the current Dynamic Island activity
  Future<void> endActivity() async {
    try {
      await platform.invokeMethod('endActivity');
      _currentActivityId = null;
    } catch (e) {
      // Silently ignore for non-iOS platforms or older iOS versions
    }
  }

  /// Stream for play/pause button taps from Dynamic Island
  Stream<void> get onPlayPause => _playPauseController.stream;

  /// Stream for skip forward button taps from Dynamic Island
  Stream<void> get onSkipForward => _skipForwardController.stream;

  /// Dispose resources
  void dispose() {
    _playPauseController.close();
    _skipForwardController.close();
  }
}
