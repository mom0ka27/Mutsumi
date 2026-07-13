import 'package:flutter/material.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.keyboardType,
    this.hintText,
    this.prefixIcon,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? hintText;
  final Widget? prefixIcon;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: prefixIcon,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class AsyncFilledButton extends StatelessWidget {
  const AsyncFilledButton({
    super.key,
    required this.busy,
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.busyLabel,
  });

  final bool busy;
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final String busyLabel;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      label: Text(busy ? busyLabel : label),
    );
  }
}

class FormStatusMessage extends StatelessWidget {
  const FormStatusMessage({
    super.key,
    required this.message,
    this.isError = false,
    this.topSpacing = 24,
  });

  final String? message;
  final bool isError;
  final double topSpacing;

  @override
  Widget build(BuildContext context) {
    if (message == null) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        SizedBox(height: topSpacing),
        Card.filled(
          color: isError ? colorScheme.errorContainer : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              message!,
              style: isError
                  ? TextStyle(color: colorScheme.onErrorContainer)
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}
