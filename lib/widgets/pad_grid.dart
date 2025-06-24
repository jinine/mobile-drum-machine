import 'package:flutter/material.dart';

class PadGrid extends StatelessWidget {
  const PadGrid({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: 16,
      itemBuilder: (context, index) {
        return Card(
          color: Colors.blueGrey,
          child: Center(child: Text('Pad \\$index')),
        );
      },
      shrinkWrap: true,
    );
  }
} 