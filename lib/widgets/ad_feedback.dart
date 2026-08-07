import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../theme/ad_tokens.dart';
import 'ad_system_notice.dart';

class AdFeedback {
  AdFeedback._();

  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static void success(
    String title,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(
      title: title,
      message: message,
      tone: AdSystemNoticeTone.success,
      duration: duration,
    );
  }

  static void error(
    String title,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(
      title: title,
      message: message,
      tone: AdSystemNoticeTone.error,
      duration: duration,
    );
  }

  static void warning(
    String title,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(
      title: title,
      message: message,
      tone: AdSystemNoticeTone.warning,
      duration: duration,
    );
  }

  static void info(
    String title,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(
      title: title,
      message: message,
      tone: AdSystemNoticeTone.info,
      duration: duration,
    );
  }

  static void dismissCurrent() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }

  static void _show({
    required String title,
    required String message,
    required AdSystemNoticeTone tone,
    required Duration duration,
  }) {
    final resolvedTitle = title.trim();
    final resolvedMessage = message.trim();
    if (resolvedTitle.isEmpty && resolvedMessage.isEmpty) {
      return;
    }

    final notice = AdSystemNoticeData(
      title: resolvedTitle,
      message: resolvedMessage,
      tone: tone,
    );

    final overlay = _resolveOverlay();
    if (overlay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final retryOverlay = _resolveOverlay();
        if (retryOverlay != null) {
          _insertNotice(retryOverlay, notice, duration);
        }
      });
      return;
    }

    _insertNotice(overlay, notice, duration);
  }

  static OverlayState? _resolveOverlay() {
    final navigatorOverlay = Get.key.currentState?.overlay;
    if (navigatorOverlay != null) return navigatorOverlay;

    final context = Get.overlayContext ?? Get.context;
    if (context == null) return null;

    return Overlay.maybeOf(context, rootOverlay: true);
  }

  static void _insertNotice(
    OverlayState overlay,
    AdSystemNoticeData notice,
    Duration duration,
  ) {
    dismissCurrent();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _AdFeedbackOverlay(
        notice: notice,
        onDismiss: () {
          if (_currentEntry == entry) {
            dismissCurrent();
          }
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);

    _dismissTimer = Timer(duration, () {
      if (_currentEntry == entry) {
        dismissCurrent();
      }
    });
  }
}

class _AdFeedbackOverlay extends StatelessWidget {
  const _AdFeedbackOverlay({
    required this.notice,
    required this.onDismiss,
  });

  final AdSystemNoticeData notice;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(
          AdSpacing.md,
          AdSpacing.sm,
          AdSpacing.md,
          0,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Material(
              color: Colors.transparent,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: AdMotion.normal,
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, -12 * (1 - value)),
                      child: child,
                    ),
                  );
                },
                child: Semantics(
                  liveRegion: true,
                  child: AdSystemNotice(
                    notice: notice,
                    onDismiss: onDismiss,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
