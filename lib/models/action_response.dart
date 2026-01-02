import 'package:adfoot/screens/success_toast.dart';

enum ToastLevel { success, info, error, none }

class ActionResponse {
  final bool success;
  final String message;
  final String? code;
  final Map<String, dynamic>? data;
  final ToastLevel toast;
  final bool retriable;

  const ActionResponse({
    required this.success,
    required this.message,
    this.code,
    this.data,
    this.toast = ToastLevel.error,
    this.retriable = false,
  });

  factory ActionResponse.fromMap(
    Map<String, dynamic>? raw, {
    ToastLevel? toastOverride,
  }) {
    final map = raw ?? <String, dynamic>{};
    final ok = map['success'] == true;
    final resolvedToast = toastOverride ??
        (ok ? ToastLevel.success : ToastLevel.error);

    return ActionResponse(
      success: ok,
      message: (map['message'] ?? (ok ? 'Action réalisée.' : 'Action impossible.')).toString(),
      code: map['code']?.toString(),
      data: (map['data'] is Map<String, dynamic>) ? map['data'] as Map<String, dynamic> : null,
      toast: resolvedToast,
      retriable: map['retriable'] == true,
    );
  }

  factory ActionResponse.failure({
    required String message,
    String? code,
    ToastLevel toast = ToastLevel.error,
    bool retriable = false,
  }) {
    return ActionResponse(
      success: false,
      message: message,
      code: code,
      toast: toast,
      retriable: retriable,
    );
  }

  factory ActionResponse.offline([String? message]) {
    return ActionResponse.failure(
      message: message ?? 'Connexion indisponible. Réessaie quand tu es en ligne.',
      code: 'offline',
      toast: ToastLevel.info,
      retriable: true,
    );
  }

  ActionResponse copyWith({
    bool? success,
    String? message,
    String? code,
    Map<String, dynamic>? data,
    ToastLevel? toast,
    bool? retriable,
  }) {
    return ActionResponse(
      success: success ?? this.success,
      message: message ?? this.message,
      code: code ?? this.code,
      data: data ?? this.data,
      toast: toast ?? this.toast,
      retriable: retriable ?? this.retriable,
    );
  }

  void showToast({bool includeSuccess = false}) {
    if (toast == ToastLevel.none) return;
    if (success && !includeSuccess) return;

    switch (toast) {
      case ToastLevel.success:
        showSuccessToast(message);
        break;
      case ToastLevel.info:
        showInfoToast(message);
        break;
      case ToastLevel.error:
        showErrorToast(message);
        break;
      case ToastLevel.none:
        break;
    }
  }
}