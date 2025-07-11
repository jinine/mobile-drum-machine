import 'package:flutter/material.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'dart:async';

class WaveformDisplay extends StatefulWidget {
  final String? filePath;
  final Duration? startTime;
  final Duration? endTime;
  final Duration? totalDuration;
  final ValueChanged<Duration>? onStartTimeChanged;
  final ValueChanged<Duration>? onEndTimeChanged;

  const WaveformDisplay({
    Key? key, 
    this.filePath,
    this.startTime,
    this.endTime,
    this.totalDuration,
    this.onStartTimeChanged,
    this.onEndTimeChanged,
  }) : super(key: key);

  @override
  State<WaveformDisplay> createState() => _WaveformDisplayState();
}

class _WaveformDisplayState extends State<WaveformDisplay> {
  late final PlayerController _controller;
  bool _loading = false;
  bool _loaded = false;
  Duration _currentPosition = Duration.zero;
  StreamSubscription? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _controller = PlayerController();
    _loadWaveform();
    _startPositionListener();
  }

  void _startPositionListener() {
    _positionSubscription?.cancel();
    _positionSubscription = _controller.onCurrentDurationChanged.listen((durationInMs) {
      if (mounted) {
        setState(() {
          _currentPosition = Duration(milliseconds: durationInMs);
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant WaveformDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _loadWaveform();
    }
  }

  Future<void> _loadWaveform() async {
    if (widget.filePath == null) return;
    setState(() {
      _loading = true;
      _loaded = false;
    });
    try {
      await _controller.preparePlayer(
        path: widget.filePath!,
        shouldExtractWaveform: true,
      );
      setState(() {
        _loaded = true;
      });
    } catch (e) {
      setState(() {
        _loaded = false;
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.filePath == null) {
      return Container(
        color: Colors.black12,
        height: 100,
        child: const Center(child: Text('No file selected')),
      );
    }
    if (_loading) {
      return Container(
        color: Colors.black12,
        height: 100,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!_loaded) {
      return Container(
        color: Colors.black12,
        height: 100,
        child: const Center(child: Text('Failed to load waveform')),
      );
    }

    return Stack(
      children: [
        Container(
          color: Colors.black12,
          height: 100,
          child: AudioFileWaveforms(
            size: const Size(double.infinity, 100),
            playerController: _controller,
            waveformType: WaveformType.fitWidth,
            enableSeekGesture: true,
            playerWaveStyle: const PlayerWaveStyle(
              seekLineColor: Colors.deepPurpleAccent,
              seekLineThickness: 2,
              showSeekLine: true,
            ),
          ),
        ),
        if (widget.startTime != null && widget.totalDuration != null)
          Positioned(
            left: (widget.startTime!.inMilliseconds / widget.totalDuration!.inMilliseconds) * MediaQuery.of(context).size.width,
            top: 0,
            bottom: 0,
            child: Container(
              width: 2,
              color: Colors.greenAccent.withOpacity(0.8),
            ),
          ),
        if (widget.endTime != null && widget.totalDuration != null)
          Positioned(
            left: (widget.endTime!.inMilliseconds / widget.totalDuration!.inMilliseconds) * MediaQuery.of(context).size.width,
            top: 0,
            bottom: 0,
            child: Container(
              width: 2,
              color: Colors.redAccent.withOpacity(0.8),
            ),
          ),
      ],
    );
  }
} 