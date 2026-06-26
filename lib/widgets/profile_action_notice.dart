import 'package:flutter/material.dart';

class ProfileActionNotice extends StatelessWidget {
  const ProfileActionNotice({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.error_outline_rounded,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(message, style: TextStyle(color: scheme.onErrorContainer)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
