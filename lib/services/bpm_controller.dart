import 'dart:async';
import 'package:just_audio/just_audio.dart';

class BpmController {
  double _bpm = 120.0;
  bool _isPlaying = false;
  bool _isRecording = false;
  bool _isOverdubbing = false;
  Timer? _bpmTimer;
  final List<Function()> _onBeatCallbacks = [];
  final List<List<int>> _recordedPattern = [];
  int _currentBeat = 0;
  int _beatsPerBar = 4;
  int _totalBars = 4;
  final AudioPlayer _metronomePlayer = AudioPlayer();
  bool _isMetronomeEnabled = true;

  BpmController() {
    _initMetronome();
  }

  // Getters
  double get bpm => _bpm;
  bool get isPlaying => _isPlaying;
  bool get isRecording => _isRecording;
  bool get isOverdubbing => _isOverdubbing;
  int get currentBeat => _currentBeat;
  int get beatsPerBar => _beatsPerBar;
  int get totalBars => _totalBars;
  int get currentBar => _currentBeat ~/ _beatsPerBar;
  int get beatInBar => _currentBeat % _beatsPerBar;
  List<List<int>> get recordedPattern => List.unmodifiable(_recordedPattern);
  bool get isMetronomeEnabled => _isMetronomeEnabled;

  Future<void> _initMetronome() async {
    try {
      // Temporarily use the hihat sample as a metronome sound
      await _metronomePlayer.setAsset('assets/samples/metronome.mp3');
      await _metronomePlayer.setVolume(0.5); // Lower volume for metronome
    } catch (e) {
      print('Error initializing metronome: $e');
    }
  }

  void toggleMetronome() {
    _isMetronomeEnabled = !_isMetronomeEnabled;
  }

  // Set BPM with validation
  void setBpm(double newBpm) {
    if (newBpm >= 40 && newBpm <= 240) {
      _bpm = newBpm;
      if (_isPlaying) {
        _restartTimer();
      }
    }
  }

  // Add callback for beat events
  void addBeatCallback(Function() callback) {
    _onBeatCallbacks.add(callback);
  }

  // Remove callback
  void removeBeatCallback(Function() callback) {
    _onBeatCallbacks.remove(callback);
  }

  // Start playback
  void start() {
    if (!_isPlaying) {
      _isPlaying = true;
      _currentBeat = 0;
      _startTimer();
    }
  }

  // Stop playback
  void stop() {
    _isPlaying = false;
    _isRecording = false;
    _currentBeat = 0;
    _bpmTimer?.cancel();
  }

  // Start recording with overdub option
  void startRecording({bool overdub = false}) {
    if (!_isRecording) {
      _isOverdubbing = overdub;
      if (!overdub) {
        _recordedPattern.clear();
      }
      _isRecording = true;
      if (!_isPlaying) {
        start();
      }
    }
  }

  // Stop recording
  void stopRecording() {
    _isRecording = false;
  }

  // Record a pad hit
  void recordPadHit(int padIndex) {
    if (_isRecording && _isPlaying) {
      // Ensure we have enough beats in the pattern
      while (_recordedPattern.length <= _currentBeat) {
        _recordedPattern.add([]);
      }
      
      if (_isOverdubbing) {
        // For overdub, add the new hit if it's not already there
        if (!_recordedPattern[_currentBeat].contains(padIndex)) {
          _recordedPattern[_currentBeat].add(padIndex);
        }
      } else {
        // For normal recording, just add the hit
        _recordedPattern[_currentBeat].add(padIndex);
      }
    }
  }

  // Clear specific bar
  void clearBar(int barIndex) {
    if (barIndex >= 0 && barIndex < totalBars) {
      final startBeat = barIndex * beatsPerBar;
      final endBeat = startBeat + beatsPerBar;
      
      for (var beat = startBeat; beat < endBeat; beat++) {
        if (beat < _recordedPattern.length) {
          _recordedPattern[beat].clear();
        }
      }
    }
  }

  // Clear all bars
  void clearRecording() {
    _recordedPattern.clear();
  }

  // Private method to start the BPM timer
  void _startTimer() {
    final interval = (60000 / _bpm).round(); // Convert BPM to milliseconds
    _bpmTimer = Timer.periodic(Duration(milliseconds: interval), (timer) async {
      _currentBeat = (_currentBeat + 1) % (_beatsPerBar * _totalBars);
      
      // Play metronome if enabled
      if (_isMetronomeEnabled) {
        try {
          // Reset position and play
          await _metronomePlayer.seek(Duration.zero);
          _metronomePlayer.play();
        } catch (e) {
          print('Error playing metronome: $e');
        }
      }
      
      // Play recorded pattern if available
      if (!_isRecording && _recordedPattern.isNotEmpty && _currentBeat < _recordedPattern.length) {
        for (final padIndex in _recordedPattern[_currentBeat]) {
          _onBeatCallbacks.forEach((callback) => callback());
        }
      }
      
      // Notify all registered callbacks
      _onBeatCallbacks.forEach((callback) => callback());
    });
  }

  // Private method to restart the timer (used when BPM changes)
  void _restartTimer() {
    _bpmTimer?.cancel();
    if (_isPlaying) {
      _startTimer();
    }
  }

  // Cleanup
  void dispose() {
    _bpmTimer?.cancel();
    _onBeatCallbacks.clear();
    _metronomePlayer.dispose();
  }

  // Set pattern length
  void setPatternLength(int bars, {int? beatsPerBar}) {
    if (bars > 0) {
      _totalBars = bars;
    }
    if (beatsPerBar != null && beatsPerBar > 0) {
      _beatsPerBar = beatsPerBar;
    }
    // Adjust current beat if it's beyond the new pattern length
    if (_currentBeat >= _totalBars * _beatsPerBar) {
      _currentBeat = 0;
    }
  }
} 