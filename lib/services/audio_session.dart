// ignore_for_file: experimental_member_use

import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:audio_session/audio_session.dart';

class AudioSessionHandler {
  late AudioSession _session;
  bool _shouldResume = false;
  final Completer<void> _ready = Completer<void>();

  static final StreamController<bool> _btController =
      StreamController<bool>.broadcast();
  static bool _isBtA2dp = false;

  static Stream<bool> get bluetoothChangedStream => _btController.stream;
  static bool get isBluetoothA2dpConnected => _isBtA2dp;

  Future<void> get ready => _ready.future;

  Future<bool> setActive(bool active) {
    return _session.setActive(active);
  }

  AudioSessionHandler() {
    initSession().whenComplete(() {
      if (!_ready.isCompleted) _ready.complete();
    });
  }

  Future<void> initSession() async {
    _session = await AudioSession.instance;
    _session.configure(const AudioSessionConfiguration.music());

    _session.interruptionEventStream.listen(_onInterrupted);

    // 耳机拔出暂停
    _session.becomingNoisyEventStream.listen((_) {
      videoPlayerServiceHandler?.onPause?.call() ??
          PlPlayerController.pauseIfExists();
    });

    // 蓝牙 A2DP 自动切换
    _session.devicesStream.listen((devices) {
      final btConnected = devices.any(
        (d) => d.type == AudioDeviceType.bluetoothA2dp && d.isOutput,
      );
      _isBtA2dp = btConnected;
      if (Pref.btAutoSwitch) {
        final delay = btConnected ? Pref.audioDelay : 0.0;
        PlPlayerController.setAudioDelayIfExists(delay);
      }
      _btController.add(btConnected);
    });

    // 初始检查
    try {
      final devices = await _session.getDevices(includeInputs: false);
      _isBtA2dp = devices.any(
        (d) => d.type == AudioDeviceType.bluetoothA2dp && d.isOutput,
      );
      _btController.add(_isBtA2dp);
      // 启动时若已连蓝牙，devicesStream 不会再发“变化”事件，需主动应用一次。
      if (Pref.btAutoSwitch) {
        PlPlayerController.setAudioDelayIfExists(
          _isBtA2dp ? Pref.audioDelay : 0.0,
        );
      }
    } catch (_) {}
  }

  void _onInterrupted(AudioInterruptionEvent event) {
    if (event.begin) {
      final player = PlPlayerController.instance;
      switch (event.type) {
        case .duck:
          if (player != null && player.playerStatus.isPlaying) {
            player.setVolume(player.volume.value * 0.5, showIndicator: false);
          }
        case .pause:
        case .unknown:
          if (videoPlayerServiceHandler?.isPlaying?.call() == true) {
            _shouldResume = true;
            videoPlayerServiceHandler?.onPause?.call();
          } else if (player != null && player.playerStatus.isPlaying) {
            _shouldResume = true;
            player.pause(isInterrupt: true);
          }
      }
    } else {
      switch (event.type) {
        case .duck:
          final player = PlPlayerController.instance;
          player?.setVolume(player.volume.value * 2, showIndicator: false);
        case .pause:
          if (_shouldResume) {
            _shouldResume = false;
            videoPlayerServiceHandler?.onPlay?.call() ??
                PlPlayerController.instance?.play();
          }
        case .unknown:
      }
    }
  }
}
