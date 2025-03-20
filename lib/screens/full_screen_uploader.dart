import 'package:flutter/material.dart';
import 'package:get/get.dart';

class FullScreenUploader extends StatelessWidget {
  final RxDouble progress;

  const FullScreenUploader({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.9),
      child: Center(
        child: Obx(() {
          double value = progress.value;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    height: 130,
                    width: 130,
                    child: CircularProgressIndicator(
                      strokeWidth: 8,
                      value: value,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      backgroundColor: Colors.grey[700],
                    ),
                  ),
                  Text(
                    '${(value * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 24,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              const Text(
                'Téléversement en cours...',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
