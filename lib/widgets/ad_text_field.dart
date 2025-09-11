import 'package:flutter/material.dart';
import '../theme/ad_colors.dart';

class AdTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType keyboardType;
  final bool isPassword;
  final String? hint;
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
    this.hint,
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
    return TextFormField(
      controller: widget.controller,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      obscureText: widget.isPassword ? _obscure : false,
      validator: widget.validator,
      onFieldSubmitted: (_) => widget.onSubmitted?.call(),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        prefixIcon: widget.prefixIcon,
        suffixIcon: widget.isPassword
            ? IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: AdColors.brand),
              )
            : widget.suffix,
      ),
    );
  }
}
