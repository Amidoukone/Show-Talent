import 'package:flutter/material.dart';

import '../theme/ad_tokens.dart';

class AdTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType keyboardType;
  final bool isPassword;
  final bool enabled;
  final String? hint;
  final String? helper;
  final int maxLines;
  final TextInputAction textInputAction;
  final FormFieldValidator<String>? validator;
  final Widget? prefixIcon;
  final Widget? suffix;
  final VoidCallback? onSubmitted;

  const AdTextField({
    super.key,
    required this.controller,
    required this.label,
    this.keyboardType = TextInputType.text,
    this.isPassword = false,
    this.enabled = true,
    this.hint,
    this.helper,
    this.maxLines = 1,
    this.textInputAction = TextInputAction.next,
    this.validator,
    this.prefixIcon,
    this.suffix,
    this.onSubmitted,
  });

  @override
  State<AdTextField> createState() => _AdTextFieldState();
}

class _AdTextFieldState extends State<AdTextField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return TextFormField(
      controller: widget.controller,
      enabled: widget.enabled,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      maxLines: widget.isPassword ? 1 : widget.maxLines,
      obscureText: widget.isPassword ? _obscure : false,
      validator: widget.validator,
      onFieldSubmitted: (_) => widget.onSubmitted?.call(),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        helperText: widget.helper,
        prefixIcon: widget.prefixIcon,
        suffixIcon: widget.isPassword
            ? IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility,
                  color: cs.primary,
                ),
              )
            : widget.suffix,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AdSpacing.md,
          vertical: AdSpacing.sm,
        ),
      ),
    );
  }
}
