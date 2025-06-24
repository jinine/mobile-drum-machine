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
  final AudioPlayer player = AudioPlayer();

  void dispose() {
    player.dispose();
  }
}

class _HomeScreenState extends State<HomeScreen> {
  final List<_PadData> _pads = List.generate(9, (_) => _PadData());
  int? _editingPadIndex;

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
      setState(() {
        _pads[padIndex].filePath = result.files.single.path;
      });
      await _pads[padIndex].player.setFilePath(_pads[padIndex].filePath!);
    }
  }

  void _showPadOptions(int padIndex) async {
    final pad = _pads[padIndex];
    if (pad.filePath == null) {
      await _pickFileForPad(padIndex);
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

  void _playPad(int padIndex) {
    final pad = _pads[padIndex];
    if (pad.filePath != null) {
      pad.player.seek(Duration.zero);
      pad.player.play();
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
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
} 