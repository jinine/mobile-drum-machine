import 'package:flutter/material.dart';
import 'package:audio_waveforms/audio_waveforms.dart';

class WaveformDisplay extends StatefulWidget {
  final String? filePath;
  const WaveformDisplay({Key? key, this.filePath}) : super(key: key);

  @override
  State<WaveformDisplay> createState() => _WaveformDisplayState();
}

class _WaveformDisplayState extends State<WaveformDisplay> {
  late final PlayerController _controller;
  bool _loading = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _controller = PlayerController();
    _loadWaveform();
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
    return Container(
      color: Colors.black12,
      height: 100,
      child: AudioFileWaveforms(
        size: const Size(double.infinity, 100),
        playerController: _controller,
        waveformType: WaveformType.fitWidth,
        enableSeekGesture: true,
      ),
    );
  }
} 