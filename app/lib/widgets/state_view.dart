import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';

/// The three calm screens that replace a list or a page that cannot be shown.
enum StateKind { offline, empty, error }

/// Empty, offline and error states, one look everywhere: an icon in a circle, a title, ONE line that says what happened
/// (on errors: that coins and progress are safe), one primary button and an optional quiet second one.
/// Never a raw error code and never English text. An offline or error state retries by itself when the connection
/// returns ([onBackOnline], called once per return).
class StateView extends StatefulWidget {
  const StateView({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.onBackOnline,
  });

  final IconData icon;
  final String title, body, primaryLabel;
  final FutureOr<void> Function() onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Called when the phone goes from offline to online while this view is on screen (the screen reloads itself).
  final VoidCallback? onBackOnline;

  /// No internet. [body] defaults to the standard line (coins and progress are safe).
  factory StateView.offline({
    Key? key,
    required FutureOr<void> Function() onRetry,
    String? body,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) =>
      StateView(
        key: key,
        icon: Icons.wifi_off_rounded,
        title: 'خط تلفن قطعه',
        body: body ?? 'به اینترنت وصل نیستی. سکه و پیشرفتت سر جاشه؛ وقتی خط برگشت، خودش تازه می‌شه.',
        primaryLabel: 'دوباره امتحان کن',
        onPrimary: onRetry,
        secondaryLabel: secondaryLabel,
        onSecondary: onSecondary,
        onBackOnline: () => onRetry(),
      );

  /// The server did not answer, or answered with an error (it also retries by itself when the line comes back).
  factory StateView.error({
    Key? key,
    required FutureOr<void> Function() onRetry,
    String? body,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) =>
      StateView(
        key: key,
        icon: Icons.cloud_off_rounded,
        title: 'پرونده‌خانه یه لحظه شلوغه',
        body: body ?? 'جواب سرور نرسید. چیزی از سکه‌ها یا پیشرفتت کم نشده؛ چند ثانیه دیگه دوباره امتحان کن.',
        primaryLabel: 'دوباره امتحان کن',
        onPrimary: onRetry,
        secondaryLabel: secondaryLabel,
        onSecondary: onSecondary,
        onBackOnline: () => onRetry(),
      );

  /// Nothing here yet. An empty page always has a next step (the button).
  factory StateView.empty({
    Key? key,
    required String title,
    required String body,
    required String primaryLabel,
    required FutureOr<void> Function() onPrimary,
    IconData icon = Icons.folder_open_rounded,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) =>
      StateView(
        key: key,
        icon: icon,
        title: title,
        body: body,
        primaryLabel: primaryLabel,
        onPrimary: onPrimary,
        secondaryLabel: secondaryLabel,
        onSecondary: onSecondary,
      );

  /// The right view for a failed request: offline when the phone has no connection to the server, else the error view.
  /// A refusal that carries its own Persian sentence (too many requests, a business rule) keeps that sentence.
  factory StateView.forError(
    Object e, {
    Key? key,
    required FutureOr<void> Function() onRetry,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) {
    // decided by what went wrong, not by Api.online: a down server also flips `online` to false
    final kind = Api.failKind(e);
    if (kind == FailKind.offline) {
      return StateView.offline(key: key, onRetry: onRetry, secondaryLabel: secondaryLabel, onSecondary: onSecondary);
    }
    final own = kind == FailKind.business || (e is ApiException && e.rateLimited);
    return StateView.error(
        key: key,
        onRetry: onRetry,
        body: own ? Api.friendly(e) : null,
        secondaryLabel: secondaryLabel,
        onSecondary: onSecondary);
  }

  @override
  State<StateView> createState() => _StateViewState();
}

class _StateViewState extends State<StateView> {
  bool _wasOnline = Api.i.online;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.onBackOnline != null) Api.i.addListener(_onApi);
  }

  @override
  void dispose() {
    Api.i.removeListener(_onApi);
    super.dispose();
  }

  void _onApi() {
    final cameBack = Api.i.online && !_wasOnline;
    _wasOnline = Api.i.online;
    if (cameBack && mounted) widget.onBackOnline?.call();
  }

  Future<void> _primary() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPrimary();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 112,
                      height: 112,
                      decoration: BoxDecoration(
                        color: K.night2,
                        shape: BoxShape.circle,
                        border: Border.all(color: K.night3),
                      ),
                      child: Icon(widget.icon, size: 54, color: K.brass),
                    ),
                    const SizedBox(height: 16),
                    Text(widget.title,
                        key: const ValueKey('state-title'),
                        textAlign: TextAlign.center,
                        style: tBody(19, w: FontWeight.w900).copyWith(height: 1.5)),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Text(widget.body,
                          key: const ValueKey('state-body'),
                          textAlign: TextAlign.center,
                          style: tBody(13.5, color: K.textSoft).copyWith(height: 1.9)),
                    ),
                    const SizedBox(height: 18),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 220),
                      child: SizedBox(
                        height: 50,
                        child: FilledButton(
                          key: const ValueKey('state-primary'),
                          onPressed: _busy ? null : _primary,
                          style: FilledButton.styleFrom(
                            backgroundColor: K.brass,
                            foregroundColor: K.ink,
                            disabledBackgroundColor: K.brass.withValues(alpha: 0.5),
                            padding: const EdgeInsets.symmetric(horizontal: 22),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _busy
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: K.ink))
                              : Text(widget.primaryLabel, style: tBody(14.5, color: K.ink, w: FontWeight.w900)),
                        ),
                      ),
                    ),
                    if (widget.secondaryLabel != null && widget.onSecondary != null)
                      TextButton(
                        key: const ValueKey('state-secondary'),
                        onPressed: widget.onSecondary,
                        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                        child: Text(widget.secondaryLabel!,
                            style: tBody(13, w: FontWeight.w800).copyWith(decoration: TextDecoration.underline)),
                      ),
                  ],
                ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        // inside a list (no height given) the view just takes the height it needs
        if (!box.hasBoundedHeight) return Center(child: content);
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(constraints: BoxConstraints(minHeight: box.maxHeight), child: Center(child: content)),
        );
      },
    );
  }
}
