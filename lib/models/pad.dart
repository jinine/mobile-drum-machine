import 'sample.dart';

class Pad {
  final int id;
  final Sample? assignedSample;
  final double volume;
  final double pan;

  Pad({
    required this.id,
    this.assignedSample,
    this.volume = 1.0,
    this.pan = 0.0,
  });
} 