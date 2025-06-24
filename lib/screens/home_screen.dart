import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import '../widgets/waveform_display.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _PadData {
  String? filePath;
  final AudioPlayer player;
  bool isAsset;

  _PadData({this.filePath, required this.player, this.isAsset = false});

  void dispose() {
    player.dispose();
  }
}

class _PadEditParams {
  double start = 0.0;
  double end = 1.0; // 1.0 means 100% of the sample
  bool reverse = false;
  double speed = 1.0;
  double fadeIn = 0.0;
  double fadeOut = 0.0;
  bool loop = false;
}

class _HomeScreenState extends State<HomeScreen> {
  final List<_PadData> _pads =
      List.generate(9, (_) => _PadData(player: AudioPlayer()));
  int? _editingPadIndex;
  Map<int, _PadEditParams> _editParams = {};

  @override
  void dispose() {
    for (final pad in _pads) {
      pad.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFileForPad(int padIndex) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3'],
    );
    if (result != null && result.files.single.path != null) {
      await _loadAudioForPad(padIndex, result.files.single.path!);
    }
  }

  Future<void> _loadAudioForPad(int padIndex, String path,
      {bool isAsset = false}) async {
    final pad = _pads[padIndex];
    // Dispose the old player to release resources before creating a new one
    await pad.player.dispose();

    // Create a new player configured for low-latency playback
    final newPlayer = AudioPlayer();

    try {
      AudioSource source;
      if (isAsset) {
        source = AudioSource.asset(path);
      } else {
        source = AudioSource.file(path);
      }

      // Pre-load the audio data. This is crucial for low-latency playback.
      // The duration returned here can be useful, but we don't need it for now.
      await newPlayer.setAudioSource(source, preload: true);

      setState(() {
        // Replace the old pad data with new data including the new player
        _pads[padIndex] =
            _PadData(player: newPlayer, filePath: path, isAsset: isAsset);
      });
    } catch (e) {
      // Handle potential errors during loading
      print("Error loading audio source: $e");
      // You might want to show a dialog to the user here
    }
  }

  void _showPadOptions(int padIndex) async {
    final pad = _pads[padIndex];
    if (pad.filePath == null) {
      _showLoadSampleDialog(padIndex);
      return;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pad ${padIndex + 1} Options'),
        content: const Text('What would you like to do?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'edit'),
            child: const Text('Edit'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('Delete'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (result == 'edit') {
      setState(() {
        _editingPadIndex = padIndex;
        _editParams.putIfAbsent(padIndex, () => _PadEditParams());
      });
    } else if (result == 'delete') {
      setState(() {
        pad.filePath = null;
        pad.player.stop();
        if (_editingPadIndex == padIndex) {
          _editingPadIndex = null;
        }
      });
    }
  }

  Future<void> _showLoadSampleDialog(int padIndex) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Load Sample'),
        content: const Text('Choose a source for your audio sample.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'device'),
            child: const Text('From Device'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'preloaded'),
            child: const Text('Preloaded'),
          ),
        ],
      ),
    );

    if (result == 'device') {
      await _pickFileForPad(padIndex);
    } else if (result == 'preloaded') {
      _showPreloadedSamples(padIndex);
    }
  }

  Future<void> _showPreloadedSamples(int padIndex) async {
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifestMap = json.decode(manifestContent);
    final samplePaths = manifestMap.keys
        .where((String key) => key.startsWith('assets/samples/'))
        .toList();

    final selectedSample = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose a Sample'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: samplePaths.length,
            itemBuilder: (context, index) {
              final sampleName = samplePaths[index].split('/').last;
              return ListTile(
                title: Text(sampleName),
                onTap: () => Navigator.pop(context, samplePaths[index]),
              );
            },
          ),
        ),
      ),
    );

    if (selectedSample != null) {
      await _loadAudioForPad(padIndex, selectedSample, isAsset: true);
    }
  }

  void _playPad(int padIndex) async {
    final pad = _pads[padIndex];
    if (pad.filePath != null) {
      final params = _editParams[padIndex];

      // If pad is currently looping, tapping it again will stop it.
      if (pad.player.playing && pad.player.loopMode == LoopMode.one) {
        await pad.player.stop();
        return;
      }

      if (pad.player.playing) {
        await pad.player.stop();
      }

      // Apply loop mode
      if (params != null) {
        await pad.player.setLoopMode(params.loop ? LoopMode.one : LoopMode.off);
      } else {
        await pad.player.setLoopMode(LoopMode.off);
      }

      // Apply speed (pitch/time-stretch)
      if (params != null) {
        await pad.player.setSpeed(params.speed);
      } else {
        await pad.player.setSpeed(1.0);
      }
      // Apply trim (start/end)
      Duration? duration = pad.player.duration;
      Duration start = Duration.zero;
      Duration? end;
      if (params != null && duration != null) {
        start = duration * params.start;
        end = duration * params.end;
        // Set the clip for the player
        await pad.player.setClip(start: start, end: end);
      } else {
        // Clear any previous clipping
        await pad.player.setClip();
      }

      await pad.player.seek(start);
      pad.player.play();

      // Handle fade in/out (approximate, not sample-accurate)
      // TODO: Re-implement fade logic correctly. The 'duration' parameter for setVolume was incorrect and caused build errors.
      /*
      if (params != null && (params.fadeIn > 0.0 || params.fadeOut > 0.0)) {
        // Reset volume to 1.0 before applying fades
        pad.player.setVolume(1.0);
        
        if (params.fadeIn > 0.0) {
          pad.player.setVolume(0.0);
          pad.player.setVolume(1.0,
              duration: Duration(milliseconds: (params.fadeIn * 1000).toInt()));
        }

        // Fade out is complex with loops. This logic is best for non-looping sounds.
        if (params.fadeOut > 0.0 && end != null && !params.loop) {
          final fadeOutDuration = Duration(milliseconds: (params.fadeOut * 1000).toInt());
          final playbackDuration = end - start;

          if (playbackDuration > fadeOutDuration) {
            Future.delayed(playbackDuration - fadeOutDuration, () {
              if (pad.player.playing) {
                pad.player.setVolume(1.0); // Ensure volume is 1 before starting fade
                pad.player.setVolume(0.0, duration: fadeOutDuration);
              }
            });
          }
        }
      }
      */
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Drum Pads')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: 9,
                itemBuilder: (context, index) {
                  final pad = _pads[index];
                  return GestureDetector(
                    onTap: () => _playPad(index),
                    onLongPress: () => _showPadOptions(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      decoration: BoxDecoration(
                        color: pad.filePath == null
                            ? const Color(0xFF23242B)
                            : Colors.deepPurpleAccent.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          if (pad.filePath != null)
                            BoxShadow(
                              color: Colors.deepPurpleAccent.withOpacity(0.4),
                              blurRadius: 16,
                              spreadRadius: 2,
                              offset: const Offset(0, 4),
                            ),
                        ],
                        border: Border.all(
                          color: pad.filePath == null
                              ? Colors.white10
                              : Colors.deepPurpleAccent,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              pad.filePath == null ? Icons.music_note : Icons.audiotrack,
                              color: pad.filePath == null ? Colors.white38 : Colors.white,
                              size: 36,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Pad ${index + 1}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1.1,
                              ),
                            ),
                            if (pad.filePath == null)
                              const Text(
                                'Hold to load',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white38,
                                  fontFamily: 'RobotoMono',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_editingPadIndex != null && _pads[_editingPadIndex!].filePath != null)
              Container(
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF23242B),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.deepPurpleAccent.withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Editing Pad ${_editingPadIndex! + 1}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54),
                          onPressed: () {
                            setState(() {
                              _editingPadIndex = null;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    WaveformDisplay(filePath: _pads[_editingPadIndex!].filePath),
                    const SizedBox(height: 16),
                    _buildEditingControls(_editingPadIndex!),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditingControls(int padIndex) {
    final params = _editParams[padIndex]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Trim:', style: TextStyle(color: Colors.white70)),
            Expanded(
              child: RangeSlider(
                values: RangeValues(params.start, params.end),
                min: 0.0,
                max: 1.0,
                divisions: 100,
                labels: RangeLabels(
                  (params.start * 100).toStringAsFixed(0) + '%',
                  (params.end * 100).toStringAsFixed(0) + '%',
                ),
                onChanged: (values) {
                  setState(() {
                    params.start = values.start;
                    params.end = values.end;
                  });
                },
              ),
            ),
          ],
        ),
        Row(
          children: [
            const Text('Reverse:', style: TextStyle(color: Colors.white70)),
            Switch(
              value: params.reverse,
              onChanged: (val) {
                setState(() {
                  params.reverse = val;
                });
              },
            ),
            const SizedBox(width: 16),
            const Text('Loop:', style: TextStyle(color: Colors.white70)),
            Switch(
              value: params.loop,
              onChanged: (val) {
                setState(() {
                  params.loop = val;
                });
              },
            ),
          ],
        ),
        Row(
          children: [
            const Text('Speed:', style: TextStyle(color: Colors.white70)),
            Expanded(
              child: Slider(
                value: params.speed,
                min: 0.5,
                max: 2.0,
                divisions: 15,
                label: params.speed.toStringAsFixed(2) + 'x',
                onChanged: (val) {
                  setState(() {
                    params.speed = val;
                  });
                },
              ),
            ),
          ],
        ),
        Row(
          children: [
            const Text('Fade In:', style: TextStyle(color: Colors.white70)),
            Expanded(
              child: Slider(
                value: params.fadeIn,
                min: 0.0,
                max: 2.0,
                divisions: 20,
                label: params.fadeIn.toStringAsFixed(2) + 's',
                onChanged: (val) {
                  setState(() {
                    params.fadeIn = val;
                  });
                },
              ),
            ),
            const SizedBox(width: 16),
            const Text('Fade Out:', style: TextStyle(color: Colors.white70)),
            Expanded(
              child: Slider(
                value: params.fadeOut,
                min: 0.0,
                max: 2.0,
                divisions: 20,
                label: params.fadeOut.toStringAsFixed(2) + 's',
                onChanged: (val) {
                  setState(() {
                    params.fadeOut = val;
                  });
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
} 