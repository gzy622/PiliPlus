import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/pages/setting/models/play_settings.dart' show kMaxVolume;
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/services/audio_session.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';

const _axisMaxMs = 1200.0;
const _dripMarkMs = 600.0;
const _sweepDuration = Duration(milliseconds: 2500);
const _soundIntervalMs = 400.0;
const _axisPerRealMs = _axisMaxMs / 2500.0;
const _da1MarkMs = _dripMarkMs - 2 * _soundIntervalMs * _axisPerRealMs;
const _da2MarkMs = _dripMarkMs - _soundIntervalMs * _axisPerRealMs;

const _da1RealMs = 450;
const _da2RealMs = 850;
const _dripRealMs = 1250;
const _roundAudioMs = 1600;

/// 校准专用音量；100 已够响，过高易失真发糊。
const _calibVolume = 100.0;

const _warmupRounds = 3;
const _measureRounds = 8;
const _maxValidOffsetMs = 900.0;
const _outlierMs = 120.0;
const _roundGap = Duration(milliseconds: 700);
const _seekSettle = Duration(milliseconds: 120);

class AudioDelayCalibPage extends StatefulWidget {
  const AudioDelayCalibPage({super.key});

  @override
  State<AudioDelayCalibPage> createState() => _AudioDelayCalibPageState();
}

enum _CalibrationState { idle, running, result }

class _AudioDelayCalibPageState extends State<AudioDelayCalibPage>
    with SingleTickerProviderStateMixin {
  _CalibrationState _state = _CalibrationState.idle;
  late final AnimationController _cursor;
  final _offsetsMs = <double>[];
  final _stopwatch = Stopwatch();

  Player? _player;
  File? _roundFile;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _btSub;

  int _roundIndex = 0;
  bool _dripFired = false;
  bool _roundClosed = false;
  bool _errorToastShown = false;
  bool _preparing = false;
  DateTime? _lastInvalidTapAt;
  int? _dripScheduleUs;
  double? _lastOffsetMs;
  double? _tapMarkMs;
  double? _meanOffsetMs;
  bool _btWarned = false;
  bool? _btAtStart;

  bool get _inWarmup => _roundIndex < _warmupRounds;

  @override
  void initState() {
    super.initState();
    _cursor = AnimationController(vsync: this, duration: _sweepDuration)
      ..addListener(_onCursorTick)
      ..addStatusListener(_onCursorStatus);
  }

  @override
  void dispose() {
    _btSub?.cancel();
    _errorSub?.cancel();
    _cursor.dispose();
    _stopwatch.stop();
    _player?.dispose();
    _roundFile?.delete().ignore();
    super.dispose();
  }

  Future<Player> _createAlignedPlayer() {
    final opt = <String, String>{
      'volume': _calibVolume.toString(),
      'volume-max': kMaxVolume.toString(),
      if (Platform.isAndroid) 'ao': Pref.audioOutput,
    };
    return Player.create(
      configuration: PlayerConfiguration(options: opt),
    );
  }

  Future<void> _seekToStart(Player player) async {
    try {
      if (player.state.playing) {
        await player.pause();
      }
      await player.seek(Duration.zero);
      await Future<void>.delayed(_seekSettle);
      // 若仍未回到起点，重新 open 一次兜底。
      if (player.state.position > const Duration(milliseconds: 40)) {
        await player.open(
          Media(Uri.file(_roundFile!.path).toString()),
          play: false,
        );
        await Future<void>.delayed(_seekSettle);
      }
    } catch (_) {
      await player.open(
        Media(Uri.file(_roundFile!.path).toString()),
        play: false,
      );
      await Future<void>.delayed(_seekSettle);
    }
  }

  /// 完整播完一轮，让 A2DP/mpv 进入稳态，避免首轮丢声、偏大延迟。
  Future<void> _primeFullRound(Player player) async {
    await player.setVolume(_calibVolume);
    await _seekToStart(player);
    await player.play();
    await Future<void>.delayed(
      const Duration(milliseconds: _roundAudioMs + 150),
    );
    await player.pause();
    await _seekToStart(player);
  }

  Future<void> _start() async {
    _cursor
      ..stop()
      ..value = 0;
    _offsetsMs.clear();
    _roundIndex = 0;
    _lastOffsetMs = null;
    _tapMarkMs = null;
    _meanOffsetMs = null;
    _errorToastShown = false;
    _lastInvalidTapAt = null;
    _btWarned = false;
    _preparing = true;
    _btAtStart = AudioSessionHandler.isBluetoothA2dpConnected;
    setState(() => _state = _CalibrationState.running);

    if (_btAtStart != true && !_btWarned) {
      _btWarned = true;
      SmartDialog.showToast('未检测到蓝牙 A2DP，测得值可能与蓝牙观看不一致');
    }

    try {
      await PlPlayerController.pauseIfExists();
      await audioSessionHandler?.setActive(true);

      _player ??= await _createAlignedPlayer();
      _errorSub ??= _player!.stream.error.listen(_onPlayerError);
      // 音量/波形变更后强制重生成，避免沿用旧的小音量文件。
      final old = _roundFile;
      _roundFile = null;
      if (old != null) {
        try {
          await old.delete();
        } catch (_) {}
      }
      _roundFile = await _createRoundToneFile();

      await _player!.setVolume(_calibVolume);
      await _player!.open(
        Media(Uri.file(_roundFile!.path).toString()),
        play: false,
      );
      await _primeFullRound(_player!);

      _btSub?.cancel();
      _btSub = AudioSessionHandler.bluetoothChangedStream.listen(_onBtChanged);
      _stopwatch
        ..reset()
        ..start();
      _preparing = false;
      if (mounted) setState(() {});
      await _beginRound();
    } catch (e) {
      _preparing = false;
      _cursor.stop();
      _stopwatch.stop();
      if (mounted) {
        setState(() => _state = _CalibrationState.idle);
        SmartDialog.showToast('无法初始化校准音频：$e');
      }
    }
  }

  void _onBtChanged(bool connected) {
    if (_state != _CalibrationState.running) return;
    if (_btAtStart == connected) return;
    _stopForPlayerError('输出设备已变化，请重新开始校准');
  }

  bool _isRecoverablePlayerError(String error) {
    final lower = error.toLowerCase();
    return lower.contains('mpv_error_command') ||
        lower.contains('error running') ||
        lower.contains('temporarily unavailable');
  }

  void _stopForPlayerError(String message) {
    if (!mounted || _state != _CalibrationState.running) return;
    _cursor.stop();
    _stopwatch.stop();
    setState(() => _state = _CalibrationState.idle);
    if (!_errorToastShown) {
      _errorToastShown = true;
      SmartDialog.showToast(message);
    }
  }

  void _onPlayerError(String error) {
    if (!mounted || _state != _CalibrationState.running) return;
    if (_isRecoverablePlayerError(error)) return;
    _stopForPlayerError('校准音频播放失败，请重新开始');
  }

  Future<void> _beginRound() async {
    if (!mounted || _state != _CalibrationState.running) return;
    _dripFired = false;
    _roundClosed = false;
    _tapMarkMs = null;

    final player = _player;
    if (player == null) return;

    try {
      await player.setVolume(_calibVolume);
      await _seekToStart(player);
    } catch (_) {
      _stopForPlayerError('校准音频播放失败，请重新开始');
      return;
    }

    // 先发起播放，再立刻启动游标与滴声时刻，避免 await play 拖长冷启动偏差。
    final playFuture = player.play();
    _dripScheduleUs =
        _stopwatch.elapsedMicroseconds +
        _dripRealMs * Duration.microsecondsPerMillisecond;
    _cursor
      ..stop()
      ..reset()
      ..forward();
    if (mounted) setState(() {});
    try {
      await playFuture;
    } catch (_) {
      _stopForPlayerError('校准音频播放失败，请重新开始');
    }
  }

  void _onCursorTick() {
    if (_state != _CalibrationState.running || _roundClosed) return;
    final axisMs = _cursor.value * _axisMaxMs;
    if (!_dripFired && axisMs >= _dripMarkMs) {
      _dripFired = true;
      setState(() {});
    }
  }

  void _onCursorStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_state != _CalibrationState.running || _roundClosed) return;
    _roundClosed = true;
    SmartDialog.showToast('未在听见「滴」时点按，本轮重试');
    Future<void>.delayed(_roundGap, () {
      if (mounted && _state == _CalibrationState.running) _beginRound();
    });
  }

  void _tap() {
    if (_state != _CalibrationState.running || _roundClosed) return;
    if (!_dripFired || _dripScheduleUs == null) {
      _toastInvalid('请在听见「滴」声时再点按');
      return;
    }
    final nowUs = _stopwatch.elapsedMicroseconds;
    final offsetMs =
        (nowUs - _dripScheduleUs!) / Duration.microsecondsPerMillisecond;
    if (offsetMs < 0 || offsetMs > _maxValidOffsetMs) {
      _toastInvalid('偏移超出范围，未计入，请在听见「滴」时点按');
      return;
    }

    HapticFeedback.selectionClick();
    _roundClosed = true;
    _cursor.stop();
    _player?.pause();
    _lastOffsetMs = offsetMs;
    // 真实时间偏移需按轴速换算到数轴坐标（1200 轴ms ≈ 2500 真实ms），
    // 再把游标停在同一位置，避免标记与游标错位。
    final markMs =
        (_dripMarkMs + offsetMs * _axisPerRealMs).clamp(0.0, _axisMaxMs);
    _tapMarkMs = markMs;
    _cursor.value = markMs / _axisMaxMs;

    if (!_inWarmup) {
      _offsetsMs.add(offsetMs);
    }

    final measureComplete = !_inWarmup && _offsetsMs.length >= _measureRounds;
    if (measureComplete) {
      _finish();
      return;
    }

    _roundIndex += 1;
    setState(() {});
    Future<void>.delayed(_roundGap, () {
      if (mounted && _state == _CalibrationState.running) _beginRound();
    });
  }

  void _toastInvalid(String msg) {
    final last = _lastInvalidTapAt;
    if (last == null ||
        DateTime.now().difference(last) > const Duration(seconds: 1)) {
      _lastInvalidTapAt = DateTime.now();
      SmartDialog.showToast(msg);
    }
  }

  void _finish() {
    _cursor.stop();
    _stopwatch.stop();
    _player?.pause();
    final sorted = [..._offsetsMs]..sort();
    final median = sorted[sorted.length ~/ 2];
    final valid =
        _offsetsMs.where((v) => (v - median).abs() <= _outlierMs).toList();
    final values = valid.isEmpty ? _offsetsMs : valid;
    _meanOffsetMs = values.reduce((a, b) => a + b) / values.length;
    setState(() => _state = _CalibrationState.result);
  }

  void _reset() {
    _cursor
      ..stop()
      ..value = 0;
    _stopwatch
      ..stop()
      ..reset();
    _roundClosed = true;
    _preparing = false;
    _player?.pause();
    setState(() {
      _state = _CalibrationState.idle;
      _lastOffsetMs = null;
      _tapMarkMs = null;
      _meanOffsetMs = null;
      _offsetsMs.clear();
      _roundIndex = 0;
    });
  }

  Future<void> _apply() async {
    final mean = _meanOffsetMs;
    if (mean == null) return;
    final value = (-mean / 1000.0).clamp(-5.0, 5.0).toDouble();
    await GStorage.setting.put(SettingBoxKey.audioDelay, value);
    // 校准面向蓝牙：开启自动切换，避免扬声器也被加上补偿。
    if (!Pref.btAutoSwitch) {
      await GStorage.setting.put(SettingBoxKey.btAutoSwitch, true);
    }
    final toApply = PlPlayerController.effectiveAudioDelay();
    final applied = PlPlayerController.setAudioDelayIfExists(toApply);
    final btOn = AudioSessionHandler.isBluetoothA2dpConnected;
    if (applied == null) {
      SmartDialog.showToast(
        btOn
            ? '已保存 ${value.toStringAsFixed(2)}s，下次播放生效'
            : '已保存 ${value.toStringAsFixed(2)}s；连接蓝牙后自动应用',
      );
    } else {
      SmartDialog.showToast(
        btOn
            ? '已应用，mpv audio-delay=${applied}s'
            : '已保存；当前非蓝牙，连接后自动应用（mpv=${applied}s）',
      );
    }
    if (mounted) Get.back(result: value);
  }

  Future<void> _previewSound() async {
    try {
      await PlPlayerController.pauseIfExists();
      await audioSessionHandler?.setActive(true);
      _player ??= await _createAlignedPlayer();
      _errorSub ??= _player!.stream.error.listen(_onPlayerError);
      await _roundFile?.delete();
      _roundFile = null;
      _roundFile = await _createRoundToneFile();
      await _player!.setVolume(_calibVolume);
      await _player!.open(
        Media(Uri.file(_roundFile!.path).toString()),
        play: true,
      );
      SmartDialog.showToast('正在试听「哒~哒~滴」');
    } catch (e) {
      SmartDialog.showToast('试听失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SimpleScaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('音画延迟校准'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _state == _CalibrationState.running ? _tap : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scheme.surface,
                Color.lerp(scheme.surface, scheme.primaryContainer, 0.22)!,
                scheme.surface,
              ],
              stops: const [0, 0.45, 1],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: switch (_state) {
                _CalibrationState.idle => _buildIdle(scheme),
                _CalibrationState.running => _buildRunning(scheme),
                _CalibrationState.result => _buildResult(scheme),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIdle(ColorScheme scheme) {
    return Column(
      children: [
        const Spacer(flex: 2),
        SizedBox(
          width: 160,
          height: 160,
          child: CustomPaint(
            painter: _IdleRingsPainter(
              color: scheme.primary,
              soft: scheme.primaryContainer,
            ),
            child: Icon(
              Icons.headphones,
              size: 64,
              color: scheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          '蓝牙音画延迟校准',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '请佩戴将用于看视频的同一副耳机。\n'
          '游标扫过时会发出「哒~哒~滴」，听见最后一声立刻点按。',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '前 3 轮适应 · 后 8 轮计入',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: scheme.primary,
          ),
        ),
        const Spacer(flex: 3),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('开始校准'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: _previewSound,
          icon: const Icon(Icons.volume_up_rounded),
          label: const Text('试听校准音'),
        ),
      ],
    );
  }

  Widget _buildRunning(ColorScheme scheme) {
    if (_preparing) {
      return Column(
        children: [
          const Spacer(),
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(color: scheme.primary),
          ),
          const SizedBox(height: 20),
          Text(
            '正在预热音频通路…',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '完整预热音频通路，随后开始「哒 · 哒 · 滴」',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          TextButton(onPressed: _reset, child: const Text('取消')),
        ],
      );
    }

    final totalSteps = _warmupRounds + _measureRounds;
    final step = _roundIndex.clamp(0, totalSteps - 1);
    final hint = _lastOffsetMs != null
        ? '最近 ${_lastOffsetMs!.toStringAsFixed(0)} ms'
        : (_dripFired ? '听见「滴」——点按标记' : '跟随「哒 · 哒 · 滴」');

    return Column(
      children: [
        const SizedBox(height: 8),
        _RoundStepper(
          warmup: _warmupRounds,
          measure: _measureRounds,
          current: step,
          inWarmup: _inWarmup,
          scheme: scheme,
        ),
        const SizedBox(height: 18),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: Theme.of(context).textTheme.titleMedium!.copyWith(
            color: _dripFired ? scheme.primary : scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
          child: Text(hint),
        ),
        const Spacer(),
        SizedBox(
          height: 168,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: _cursor,
            builder: (context, _) {
              return CustomPaint(
                painter: _TimelinePainter(
                  axisMaxMs: _axisMaxMs,
                  dripMarkMs: _dripMarkMs,
                  da1MarkMs: _da1MarkMs,
                  da2MarkMs: _da2MarkMs,
                  cursorMs: _cursor.value * _axisMaxMs,
                  tapMarkMs: _tapMarkMs,
                  dripActive: _dripFired,
                  primary: scheme.primary,
                  onPrimary: scheme.onPrimary,
                  onSurface: scheme.onSurface,
                  outline: scheme.outlineVariant,
                  track: scheme.surfaceContainerHighest,
                  glow: scheme.primary.withValues(alpha: 0.35),
                ),
              );
            },
          ),
        ),
        const Spacer(),
        Text(
          '点按屏幕空白处标记',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _reset,
          child: const Text('取消'),
        ),
      ],
    );
  }

  Widget _buildResult(ColorScheme scheme) {
    final mean = _meanOffsetMs!;
    final suggested = (-mean / 1000.0).clamp(-5.0, 5.0).toDouble();
    return Column(
      children: [
        const Spacer(flex: 2),
        Icon(Icons.check_circle_rounded, size: 56, color: scheme.primary),
        const SizedBox(height: 20),
        Text(
          '测得延迟',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: mean.toStringAsFixed(0),
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.5,
                  color: scheme.onSurface,
                ),
              ),
              TextSpan(
                text: ' ms',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Text(
                '将写入 audio-delay',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${suggested.toStringAsFixed(2)} s',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '并开启蓝牙自动切换',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        const Spacer(flex: 3),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _apply,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('应用并返回'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: _reset, child: const Text('重测')),
      ],
    );
  }
}

class _RoundStepper extends StatelessWidget {
  const _RoundStepper({
    required this.warmup,
    required this.measure,
    required this.current,
    required this.inWarmup,
    required this.scheme,
  });

  final int warmup;
  final int measure;
  final int current;
  final bool inWarmup;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final label = inWarmup
        ? '适应 ${current + 1}/$warmup'
        : '测量 ${current - warmup + 1}/$measure';
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < warmup + measure; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: i <= current
                        ? (i < warmup
                              ? scheme.tertiary.withValues(alpha: 0.7)
                              : scheme.primary)
                        : scheme.surfaceContainerHighest,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _IdleRingsPainter extends CustomPainter {
  _IdleRingsPainter({required this.color, required this.soft});

  final Color color;
  final Color soft;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    for (var i = 3; i >= 1; i--) {
      canvas.drawCircle(
        c,
        28.0 + i * 18,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = color.withValues(alpha: 0.12 * (4 - i)),
      );
    }
    canvas.drawCircle(
      c,
      52,
      Paint()..color = soft.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _IdleRingsPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.soft != soft;
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.axisMaxMs,
    required this.dripMarkMs,
    required this.da1MarkMs,
    required this.da2MarkMs,
    required this.cursorMs,
    required this.tapMarkMs,
    required this.dripActive,
    required this.primary,
    required this.onPrimary,
    required this.onSurface,
    required this.outline,
    required this.track,
    required this.glow,
  });

  final double axisMaxMs;
  final double dripMarkMs;
  final double da1MarkMs;
  final double da2MarkMs;
  final double cursorMs;
  final double? tapMarkMs;
  final bool dripActive;
  final Color primary;
  final Color onPrimary;
  final Color onSurface;
  final Color outline;
  final Color track;
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 20.0;
    final right = size.width - 20.0;
    final width = right - left;
    final axisY = size.height * 0.58;

    double xOf(double ms) => left + (ms / axisMaxMs).clamp(0.0, 1.0) * width;

    // 背景光晕
    final dripX = xOf(dripMarkMs);
    canvas.drawCircle(
      Offset(dripX, axisY),
      dripActive ? 46 : 34,
      Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22)
        ..color = glow,
    );

    // 轨道
    final trackR = RRect.fromLTRBR(
      left,
      axisY - 7,
      right,
      axisY + 7,
      const Radius.circular(99),
    );
    canvas.drawRRect(trackR, Paint()..color = track);

    // 已扫过填充
    final cx = xOf(cursorMs);
    if (cx > left) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          left,
          axisY - 7,
          cx,
          axisY + 7,
          const Radius.circular(99),
        ),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(left, axisY),
            Offset(cx, axisY),
            [
              primary.withValues(alpha: 0.15),
              primary.withValues(alpha: 0.55),
            ],
          ),
      );
    }

    final labelStyle = TextStyle(
      color: onSurface.withValues(alpha: 0.55),
      fontSize: 10,
      fontWeight: FontWeight.w500,
    );
    final tp = TextPainter(textDirection: ui.TextDirection.ltr);

    for (var ms = 0; ms <= axisMaxMs; ms += 200) {
      final x = xOf(ms.toDouble());
      canvas.drawLine(
        Offset(x, axisY + 14),
        Offset(x, axisY + 20),
        Paint()
          ..color = outline
          ..strokeWidth = 1.2,
      );
      tp.text = TextSpan(text: '$ms', style: labelStyle);
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, axisY + 24));
    }

    void beatDot(double ms, {required bool major}) {
      final x = xOf(ms);
      final passed = cursorMs >= ms;
      canvas.drawCircle(
        Offset(x, axisY),
        major ? 8 : 5.5,
        Paint()
          ..color = passed
              ? primary
              : outline.withValues(alpha: 0.7),
      );
      if (major) {
        canvas.drawCircle(
          Offset(x, axisY),
          3.5,
          Paint()..color = passed ? onPrimary : track,
        );
      }
    }

    beatDot(da1MarkMs, major: false);
    beatDot(da2MarkMs, major: false);

    // 滴标记
    final markH = dripActive ? 36.0 : 28.0;
    canvas.drawLine(
      Offset(dripX, axisY - markH),
      Offset(dripX, axisY + markH),
      Paint()
        ..color = primary
        ..strokeWidth = dripActive ? 3 : 2
        ..strokeCap = StrokeCap.round,
    );
    final flag = Path()
      ..moveTo(dripX, axisY - markH)
      ..lineTo(dripX + 16, axisY - markH + 10)
      ..lineTo(dripX, axisY - markH + 20)
      ..close();
    canvas.drawPath(flag, Paint()..color = primary);
    tp.text = TextSpan(
      text: '滴',
      style: TextStyle(
        color: primary,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
    tp.layout();
    tp.paint(canvas, Offset(dripX - tp.width / 2, axisY - markH - 20));

    final tap = tapMarkMs;
    if (tap != null) {
      final tx = xOf(tap);
      canvas.drawCircle(
        Offset(tx, axisY),
        10,
        Paint()..color = primary.withValues(alpha: 0.25),
      );
      canvas.drawCircle(Offset(tx, axisY), 5, Paint()..color = primary);
    }

    // 游标光柱
    canvas.drawLine(
      Offset(cx, axisY - 48),
      Offset(cx, axisY + 28),
      Paint()
        ..color = onSurface.withValues(alpha: 0.2)
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawLine(
      Offset(cx, axisY - 48),
      Offset(cx, axisY + 28),
      Paint()
        ..color = onSurface
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    final head = Path()
      ..moveTo(cx, axisY - 54)
      ..lineTo(cx - 9, axisY - 38)
      ..lineTo(cx + 9, axisY - 38)
      ..close();
    canvas.drawPath(head, Paint()..color = onSurface);
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) {
    return oldDelegate.cursorMs != cursorMs ||
        oldDelegate.tapMarkMs != tapMarkMs ||
        oldDelegate.dripActive != dripActive ||
        oldDelegate.primary != primary;
  }
}

Future<File> _createRoundToneFile() async {
  // 文件名带版本，避免沿用旧的「片头杂音」WAV。
  final file = File('$tmpDirPath/audio_delay_calib_round_v3.wav');
  const sampleRate = 44100;
  final sampleCount = sampleRate * _roundAudioMs ~/ 1000;
  final data = ByteData(44 + sampleCount * 2);

  void u16(int offset, int value) =>
      data.setUint16(offset, value, Endian.little);
  void u32(int offset, int value) =>
      data.setUint32(offset, value, Endian.little);

  final bytes = data.buffer.asUint8List();
  // ignore: cascade_invocations
  bytes.setRange(0, 16, const [
    0x52,
    0x49,
    0x46,
    0x46,
    0,
    0,
    0,
    0,
    0x57,
    0x41,
    0x56,
    0x45,
    0x66,
    0x6D,
    0x74,
    0x20,
  ]);
  u32(4, 36 + sampleCount * 2);
  u32(16, 16);
  u16(20, 1);
  u16(22, 1);
  u32(24, sampleRate);
  u32(28, sampleRate * 2);
  u16(32, 2);
  u16(34, 16);
  bytes.setRange(36, 40, const [0x64, 0x61, 0x74, 0x61]);
  u32(40, sampleCount * 2);

  for (var i = 0; i < sampleCount; i++) {
    data.setInt16(44 + i * 2, 0, Endian.little);
  }

  // 干净短促点击：仅三声，无片头杂音。
  void writeClick({
    required int startMs,
    required double freqHz,
    required int amplitude,
    required int durationMs,
  }) {
    final start = startMs * sampleRate ~/ 1000;
    final len = durationMs * sampleRate ~/ 1000;
    for (var i = 0; i < len; i++) {
      final idx = start + i;
      if (idx < 0 || idx >= sampleCount) continue;
      final t = i / sampleRate;
      final attack = math.min(1.0, i / (sampleRate * 0.004));
      final envelope = attack * math.exp(-t * 70);
      final sample =
          (math.sin(2 * math.pi * freqHz * t) * envelope * amplitude).round();
      data.setInt16(44 + idx * 2, sample.clamp(-32767, 32767), Endian.little);
    }
  }

  // 哒、哒：稍低；滴：更高更脆，易区分。
  writeClick(
    startMs: _da1RealMs,
    freqHz: 1000,
    amplitude: 30000,
    durationMs: 55,
  );
  writeClick(
    startMs: _da2RealMs,
    freqHz: 1000,
    amplitude: 30000,
    durationMs: 55,
  );
  writeClick(
    startMs: _dripRealMs,
    freqHz: 1600,
    amplitude: 32000,
    durationMs: 45,
  );

  await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  return file;
}
