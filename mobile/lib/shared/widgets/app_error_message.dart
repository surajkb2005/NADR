import 'package:flutter/material.dart';

class AppErrorMessage extends StatelessWidget {
  const AppErrorMessage({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.error_outline_rounded),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
      ],
    );
  }
}

abstract final class AppErrorSnackBar {
  static SnackBar create(String message) {
    return SnackBar(content: AppErrorMessage(message: message));
  }
}
