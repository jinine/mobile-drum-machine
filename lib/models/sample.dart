class Sample {
  final String filePath;
  final double start;
  final double end;
  final Map<String, dynamic> metadata;

  Sample({
    required this.filePath,
    required this.start,
    required this.end,
    this.metadata = const {},
  });
} 