import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import '../widgets/waveform_display.dart';
import 'dart:async';

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
  double end = 1.0;
  Duration? totalDuration;  // Store the total duration of the sample
  Duration startTime = Duration.zero;  // Actual start time in Duration
  Duration endTime = Duration.zero;    // Actual end time in Duration
  bool reverse = false;
  double speed = 1.0;
  double fadeIn = 0.0;
  double fadeOut = 0.0;
  bool loop = false;

  // Convert percentage to Duration
  void updateTimesFromPercentages() {
    if (totalDuration != null) {
      startTime = totalDuration! * start;
      endTime = totalDuration! * end;
    }
  }

  // Convert Duration to percentage
  void updatePercentagesFromTimes() {
    if (totalDuration != null && totalDuration!.inMilliseconds > 0) {
      start = startTime.inMilliseconds / totalDuration!.inMilliseconds;
      end = endTime.inMilliseconds / totalDuration!.inMilliseconds;
    }
  }
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
      await newPlayer.setAudioSource(source, preload: true);
      
      // Get the duration and initialize edit parameters
      final duration = await newPlayer.duration;
      final params = _PadEditParams()
        ..totalDuration = duration
        ..endTime = duration ?? Duration.zero;

      setState(() {
        // Replace the old pad data with new data including the new player
        _pads[padIndex] = _PadData(player: newPlayer, filePath: path, isAsset: isAsset);
        _editParams[padIndex] = params;
      });
    } catch (e) {
      print("Error loading audio source: $e");
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

      try {
        // Create appropriate AudioSource based on parameters
        AudioSource source;
        if (pad.isAsset) {
          source = AudioSource.asset(pad.filePath!);
        } else {
          source = AudioSource.file(pad.filePath!);
        }

        // Set the audio source
        await pad.player.setAudioSource(source);

        // Apply loop mode
        await pad.player.setLoopMode(params?.loop == true ? LoopMode.one : LoopMode.off);

        // Apply speed (pitch/time-stretch)
        if (params != null) {
          await pad.player.setSpeed(params.speed);
        } else {
          await pad.player.setSpeed(1.0);
        }

        // Apply trim (start/end)
        if (params != null) {
          await pad.player.setClip(
            start: params.startTime,
            end: params.endTime,
          );

          // For reverse playback, seek to end. For normal playback, seek to start
          if (params.reverse) {
            await pad.player.seek(params.endTime);
          } else {
            await pad.player.seek(params.startTime);
          }
        } else {
          await pad.player.setClip();
          await pad.player.seek(Duration.zero);
        }

        // Reset volume to 1.0 before starting
        await pad.player.setVolume(1.0);

        // Start playback
        if (params?.reverse == true) {
          // TODO: Implement proper reverse playback
          // DISCLAIMER: Current reverse implementation is a temporary solution that produces
          // choppy audio and artifacts. This is NOT a proper reverse playback implementation.
          // A proper implementation would require:
          // 1. Sample-level audio manipulation
          // 2. Buffer reversal before playback
          // 3. Native audio processing for real-time sample reversal
          // 4. Proper handling of audio codec specifics
          //
          // This will be replaced with a proper implementation using native audio processing.
          // For now, this is just a visual demonstration and should not be used in production.
          
          // Current hacky implementation - produces choppy audio:
          final currentParams = params!; // Cache the non-null params
          final stepSize = const Duration(milliseconds: 20); // 20ms steps for "playback"
          final timer = Timer.periodic(stepSize, (timer) async {
            if (!pad.player.playing) {
              timer.cancel();
              return;
            }

            final position = await pad.player.position;
            if (position <= currentParams.startTime) {
              if (currentParams.loop) {
                // If looping, jump back to end
                await pad.player.seek(currentParams.endTime);
              } else {
                // If not looping, stop playback
                timer.cancel();
                await pad.player.stop();
              }
            } else {
              // Move backwards by stepSize - this produces choppy audio
              await pad.player.seek(position - stepSize);
            }
          });

          // Start the audio but immediately pause it
          // This ensures the audio engine is ready but we control the position
          await pad.player.play();
          await pad.player.pause();
        } else {
          pad.player.play();
        }

        // Handle fade in/out
        if (params != null && (params.fadeIn > 0.0 || params.fadeOut > 0.0)) {
          if (params.fadeIn > 0.0) {
            // Start with volume 0 and fade in
            await pad.player.setVolume(0.0);
            
            // Create a smooth fade in effect
            const steps = 50; // Number of steps for smooth fade
            final stepDuration = (params.fadeIn * 1000 / steps).round();
            for (var i = 1; i <= steps; i++) {
              if (!pad.player.playing) break; // Stop if playback was interrupted
              await pad.player.setVolume(i / steps);
              await Future.delayed(Duration(milliseconds: stepDuration));
            }
          }

          if (params.fadeOut > 0.0 && !params.loop) {
            // Calculate when to start fade out
            final totalDuration = params.endTime - params.startTime;
            final fadeOutStart = totalDuration - Duration(milliseconds: (params.fadeOut * 1000).round());
            
            // Wait until it's time to fade out
            Future.delayed(fadeOutStart, () async {
              if (!pad.player.playing) return; // Don't fade if not playing
              
              // Create a smooth fade out effect
              const steps = 50; // Number of steps for smooth fade
              final stepDuration = (params.fadeOut * 1000 / steps).round();
              for (var i = steps - 1; i >= 0; i--) {
                if (!pad.player.playing) break; // Stop if playback was interrupted
                await pad.player.setVolume(i / steps);
                await Future.delayed(Duration(milliseconds: stepDuration));
              }
            });
          }
        }
      } catch (e) {
        print('Error playing pad: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Drum Pads')),
      body: Stack(
        children: [
          Padding(
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
              ],
            ),
          ),
          if (_editingPadIndex != null && _pads[_editingPadIndex!].filePath != null)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              left: 0,
              right: 0,
              bottom: 0,
              height: MediaQuery.of(context).size.height * 0.6,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 300),
                builder: (context, value, child) {
                  return Transform.translate(
                    offset: Offset(0, (1 - value) * 100),
                    child: Opacity(
                      opacity: value,
                      child: child,
                    ),
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF23242B),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Handle bar for dragging
                      Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Editing Pad ${_editingPadIndex! + 1}',
                              style: const TextStyle(
                                fontSize: 18,
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
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16.0),
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              WaveformDisplay(
                                filePath: _pads[_editingPadIndex!].filePath,
                                startTime: _editParams[_editingPadIndex!]?.startTime,
                                endTime: _editParams[_editingPadIndex!]?.endTime,
                                totalDuration: _editParams[_editingPadIndex!]?.totalDuration,
                                onStartTimeChanged: (time) {
                                  setState(() {
                                    final params = _editParams[_editingPadIndex!]!;
                                    params.startTime = time;
                                    params.updatePercentagesFromTimes();
                                  });
                                },
                                onEndTimeChanged: (time) {
                                  setState(() {
                                    final params = _editParams[_editingPadIndex!]!;
                                    params.endTime = time;
                                    params.updatePercentagesFromTimes();
                                  });
                                },
                              ),
                              const SizedBox(height: 16),
                              _buildEditingControls(_editingPadIndex!),
                              // Add some padding at the bottom to ensure everything is visible
                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEditingControls(int padIndex) {
    final params = _editParams[padIndex]!;
    final duration = params.totalDuration;
    
    String formatDuration(Duration d) {
      final minutes = d.inMinutes;
      final seconds = (d.inMilliseconds / 1000) % 60;
      final milliseconds = d.inMilliseconds % 1000;
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toStringAsFixed(3).padLeft(6, '0')}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (duration != null) Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Text(
            'Total Duration: ${formatDuration(duration)}',
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        Row(
          children: [
            const Text('Trim:', style: TextStyle(color: Colors.white70)),
            Expanded(
              child: Column(
                children: [
                  RangeSlider(
                    values: RangeValues(params.start, params.end),
                    min: 0.0,
                    max: 1.0,
                    divisions: 1000, // Increased precision
                    labels: RangeLabels(
                      formatDuration(params.startTime),
                      formatDuration(params.endTime),
                    ),
                    onChanged: (values) {
                      setState(() {
                        params.start = values.start;
                        params.end = values.end;
                        params.updateTimesFromPercentages();
                      });
                    },
                  ),
                  // Add precise time input fields
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Start (ms)',
                            labelStyle: TextStyle(color: Colors.white70),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white30),
                            ),
                          ),
                          keyboardType: TextInputType.number,
                          initialValue: params.startTime.inMilliseconds.toString(),
                          onChanged: (value) {
                            final ms = int.tryParse(value);
                            if (ms != null && duration != null) {
                              setState(() {
                                params.startTime = Duration(milliseconds: ms.clamp(0, duration.inMilliseconds));
                                params.updatePercentagesFromTimes();
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'End (ms)',
                            labelStyle: TextStyle(color: Colors.white70),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white30),
                            ),
                          ),
                          keyboardType: TextInputType.number,
                          initialValue: params.endTime.inMilliseconds.toString(),
                          onChanged: (value) {
                            final ms = int.tryParse(value);
                            if (ms != null && duration != null) {
                              setState(() {
                                params.endTime = Duration(milliseconds: ms.clamp(0, duration.inMilliseconds));
                                params.updatePercentagesFromTimes();
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
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