// ignore_for_file: experimental_member_use

import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:audio_session/audio_session.dart';

class AudioSessionHandler {
  late AudioSession session;
  bool _playInterrupted = false;

  static final StreamController<bool> _btController =
      StreamController<bool>.broadcast();
  static bool _isBtA2dp = false;

  static Stream<bool> get bluetoothChangedStream => _btController.stream;
  static bool get isBluetoothA2dpConnected => _isBtA2dp;

  Future<bool> setActive(bool active) {
    return session.setActive(active);
  }

  AudioSessionHandler() {
    initSession();
  }

  Future<void> initSession() async {
    session = await AudioSession.instance;
    session.configure(const AudioSessionConfiguration.music());

    session.interruptionEventStream.listen((event) {
      final playerStatus = PlPlayerController.getPlayerStatusIfExists();
      if (event.begin) {
        if (playerStatus != PlayerStatus.playing) return;
        switch (event.type) {
          case AudioInterruptionType.duck:
            PlPlayerController.setVolumeIfExists(
              (PlPlayerController.getVolumeIfExists() ?? 0) * 0.5,
              showIndicator: false,
            );
            break;
          case AudioInterruptionType.pause:
            PlPlayerController.pauseIfExists(isInterrupt: true);
            _playInterrupted = true;
            break;
          case AudioInterruptionType.unknown:
            PlPlayerController.pauseIfExists(isInterrupt: true);
            _playInterrupted = true;
            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            PlPlayerController.setVolumeIfExists(
              (PlPlayerController.getVolumeIfExists() ?? 0) * 2,
              showIndicator: false,
            );
            break;
          case AudioInterruptionType.pause:
            if (_playInterrupted) PlPlayerController.playIfExists();
            break;
          case AudioInterruptionType.unknown:
            break;
        }
        _playInterrupted = false;
      }
    });

    // 耳机拔出暂停
    session.becomingNoisyEventStream.listen((_) {
      PlPlayerController.pauseIfExists();
    });

    // 蓝牙 A2DP 自动切换
    session.devicesStream.listen((devices) {
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
      final devices = await session.getDevices(includeInputs: false);
      _isBtA2dp = devices.any(
        (d) => d.type == AudioDeviceType.bluetoothA2dp && d.isOutput,
      );
      _btController.add(_isBtA2dp);
    } catch (_) {}
  }
}
