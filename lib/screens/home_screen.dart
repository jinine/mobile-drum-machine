import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import '../widgets/waveform_display.dart';
import '../services/bpm_controller.dart';
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
  final BpmController _bpmController = BpmController();
  final TextEditingController _bpmTextController = TextEditingController(text: '120.0');
  bool _isBeatActive = false;
  final Map<int, bool> _padTriggerStates = {};

  @override
  void initState() {
    super.initState();
    _bpmController.addBeatCallback(_onBeat);
  }

  @override
  void dispose() {
    _bpmController.dispose();
    _bpmTextController.dispose();
    for (final pad in _pads) {
      pad.dispose();
    }
    super.dispose();
  }

  void _onBeat(int beatIndex) {
    // Visual feedback for the beat
    setState(() {
      _isBeatActive = true;
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          _isBeatActive = false;
        });
      }
    });

    // Play any pads scheduled for this beat
    if (!_bpmController.isRecording && 
        beatIndex < _bpmController.recordedPattern.length) {
      for (final padIndex in _bpmController.recordedPattern[beatIndex]) {
        _playPad(padIndex, isSequenced: true);
      }
    }
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

  void _playPad(int padIndex, {bool isSequenced = false}) async {
    final pad = _pads[padIndex];
    if (pad.filePath != null) {
      // Only record the hit if it's not from the sequencer
      if (!isSequenced) {
        _bpmController.recordPadHit(padIndex);
      }

      // Visual feedback
      setState(() {
        _padTriggerStates[padIndex] = true;
      });
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            _padTriggerStates[padIndex] = false;
          });
        }
      });

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

        final params = _editParams[padIndex];
        if (params != null) {
          // Apply speed (pitch/time-stretch)
          await pad.player.setSpeed(params.speed);

          // Apply trim (start/end)
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

          // Apply loop mode
          await pad.player.setLoopMode(params.loop ? LoopMode.one : LoopMode.off);
        } else {
          await pad.player.setClip();
          await pad.player.seek(Duration.zero);
          await pad.player.setLoopMode(LoopMode.off);
        }

        // Reset volume to 1.0 before starting
        await pad.player.setVolume(1.0);

        // Start playback
        if (params?.reverse == true) {
          // Handle reverse playback
          final currentParams = params!; // Force non-null since we checked above
          final stepSize = const Duration(milliseconds: 20);
          final timer = Timer.periodic(stepSize, (timer) async {
            if (!pad.player.playing) {
              timer.cancel();
              return;
            }

            final position = await pad.player.position;
            if (position <= currentParams.startTime) {
              if (currentParams.loop) {
                await pad.player.seek(currentParams.endTime);
              } else {
                timer.cancel();
                await pad.player.stop();
              }
            } else {
              await pad.player.seek(position - stepSize);
            }
          });

          await pad.player.play();
          await pad.player.pause();
        } else {
          pad.player.play();
        }

        // Handle fade in/out
        if (params != null && (params.fadeIn > 0.0 || params.fadeOut > 0.0)) {
          if (params.fadeIn > 0.0) {
            await pad.player.setVolume(0.0);
            const steps = 50;
            final stepDuration = (params.fadeIn * 1000 / steps).round();
            for (var i = 1; i <= steps; i++) {
              if (!pad.player.playing) break;
              await pad.player.setVolume(i / steps);
              await Future.delayed(Duration(milliseconds: stepDuration));
            }
          }

          if (params.fadeOut > 0.0 && !params.loop) {
            final totalDuration = params.endTime - params.startTime;
            final fadeOutStart = totalDuration - Duration(milliseconds: (params.fadeOut * 1000).round());
            Future.delayed(fadeOutStart, () async {
              if (!pad.player.playing) return;
              const steps = 50;
              final stepDuration = (params.fadeOut * 1000 / steps).round();
              for (var i = steps - 1; i >= 0; i--) {
                if (!pad.player.playing) break;
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

  void _showRecordingOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF23242B),
      builder: (context) => SingleChildScrollView(
        child: Container(
          padding: EdgeInsets.fromLTRB(
            16, 16, 16, 
            MediaQuery.of(context).viewInsets.bottom + 16
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'Recording Options',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // Record options
              const Padding(
                padding: EdgeInsets.only(left: 16, bottom: 8),
                child: Text(
                  'RECORD MODE',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.fiber_manual_record, color: Colors.red),
                title: const Text('New Recording', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Clear existing pattern and start new', style: TextStyle(color: Colors.white70)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _bpmController.startRecording(overdub: false);
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline, color: Colors.green),
                title: const Text('Overdub', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Add to existing pattern', style: TextStyle(color: Colors.white70)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _bpmController.startRecording(overdub: true);
                  });
                },
              ),
              const Divider(color: Colors.white24),
              // Clear options
              const Padding(
                padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
                child: Text(
                  'CLEAR OPTIONS',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Clear All', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Delete entire pattern', style: TextStyle(color: Colors.white70)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _bpmController.clearRecording();
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.clear_all, color: Colors.orange),
                title: const Text('Clear Current Bar', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Delete only the current bar', style: TextStyle(color: Colors.white70)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _bpmController.clearBar(_bpmController.currentBar);
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drum Pads'),
        backgroundColor: const Color(0xFF1A1B22),
        elevation: 0,
      ),
      backgroundColor: const Color(0xFF15161C),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: 9,
                      itemBuilder: (context, index) => _buildPad(index),
                    ),
                  ),
                ),
                _buildTransportControls(),
              ],
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
      ),
    );
  }

  Widget _buildTransportControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: const Color(0xFF23242B),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Bar counter and transport buttons row
          SizedBox(
            height: 48,
            child: Row(
              children: [
                // Bar/Beat counter
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Bar ${_bpmController.currentBar + 1}.',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontFamily: 'RobotoMono',
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${_bpmController.beatInBar + 1}',
                        style: TextStyle(
                          color: _isBeatActive ? Colors.deepPurpleAccent : Colors.white,
                          fontFamily: 'RobotoMono',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Beat indicator
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isBeatActive ? Colors.deepPurpleAccent : Colors.white24,
                  ),
                ),
                const Spacer(),
                // Transport Controls
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Play button
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        _bpmController.isPlaying ? Icons.stop : Icons.play_arrow,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: () {
                        setState(() {
                          if (_bpmController.isPlaying) {
                            _bpmController.stop();
                          } else {
                            _bpmController.start();
                          }
                        });
                      },
                    ),
                    const SizedBox(width: 12),
                    // Record button
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        _bpmController.isRecording 
                          ? Icons.stop_circle 
                          : Icons.fiber_manual_record,
                        color: _bpmController.isRecording 
                          ? Colors.red 
                          : _bpmController.isOverdubbing 
                            ? Colors.green 
                            : Colors.white,
                        size: 28,
                      ),
                      onPressed: () {
                        if (_bpmController.isRecording) {
                          setState(() {
                            _bpmController.stopRecording();
                          });
                        } else {
                          _showRecordingOptions();
                        }
                      },
                    ),
                    const SizedBox(width: 12),
                    // Metronome button
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        Icons.music_note,
                        color: _bpmController.isMetronomeEnabled 
                          ? Colors.deepPurpleAccent 
                          : Colors.white54,
                        size: 24,
                      ),
                      onPressed: () {
                        setState(() {
                          _bpmController.toggleMetronome();
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Pattern length and BPM controls
          Row(
            children: [
              // Pattern length controls
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Bars:',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 4),
                    DropdownButton<int>(
                      value: _bpmController.totalBars,
                      dropdownColor: const Color(0xFF2D2E36),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                      ),
                      underline: Container(),
                      items: [1, 2, 4, 8, 16].map((int value) {
                        return DropdownMenuItem<int>(
                          value: value,
                          child: Text(value.toString()),
                        );
                      }).toList(),
                      onChanged: (int? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _bpmController.setPatternLength(newValue);
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // BPM controls
              Expanded(
                child: Row(
                  children: [
                    const Text(
                      'BPM',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 56,
                      height: 32,
                      child: TextField(
                        controller: _bpmTextController,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                          border: OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24),
                          ),
                        ),
                        onChanged: (value) {
                          final bpm = double.tryParse(value);
                          if (bpm != null) {
                            _bpmController.setBpm(bpm);
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: Colors.deepPurpleAccent,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.deepPurpleAccent,
                          overlayColor: Colors.deepPurpleAccent.withOpacity(0.3),
                          trackHeight: 4.0,
                        ),
                        child: Slider(
                          value: _bpmController.bpm,
                          min: 40,
                          max: 240,
                          divisions: 200,
                          label: _bpmController.bpm.toStringAsFixed(1),
                          onChanged: (value) {
                            setState(() {
                              _bpmController.setBpm(value);
                              _bpmTextController.text = value.toStringAsFixed(1);
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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

  Widget _buildPad(int index) {
    final pad = _pads[index];
    final isTriggered = _padTriggerStates[index] ?? false;
    final hasSound = pad.filePath != null;

    return GestureDetector(
      onTap: () => _playPad(index),
      onLongPress: () => _showPadOptions(index),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: hasSound
              ? isTriggered
                ? [
                    Colors.deepPurpleAccent,
                    Colors.deepPurpleAccent.shade700,
                  ]
                : [
                    const Color(0xFF2A2D3E),
                    const Color(0xFF232635),
                  ]
              : [
                  const Color(0xFF1D1E26),
                  const Color(0xFF1A1B22),
                ],
          ),
          boxShadow: [
            BoxShadow(
              color: isTriggered
                ? Colors.deepPurpleAccent.withOpacity(0.5)
                : Colors.black.withOpacity(0.3),
              blurRadius: isTriggered ? 16 : 8,
              spreadRadius: isTriggered ? 2 : 0,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(
            color: hasSound
              ? isTriggered
                ? Colors.deepPurpleAccent
                : Colors.deepPurpleAccent.withOpacity(0.3)
              : Colors.white10,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (hasSound) ...[
              Icon(
                Icons.audiotrack,
                color: isTriggered ? Colors.white : Colors.white70,
                size: 24,
              ),
              const SizedBox(height: 8),
              Text(
                'Pad ${index + 1}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isTriggered ? Colors.white : Colors.white70,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                pad.isAsset 
                  ? pad.filePath!.split('/').last.split('.').first
                  : 'Sample ${index + 1}',
                style: TextStyle(
                  fontSize: 11,
                  color: isTriggered ? Colors.white70 : Colors.white38,
                  letterSpacing: 0.2,
                ),
              ),
            ] else ...[
              const Icon(
                Icons.add,
                color: Colors.white38,
                size: 24,
              ),
              const SizedBox(height: 8),
              const Text(
                'Add Sound',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white38,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
} 