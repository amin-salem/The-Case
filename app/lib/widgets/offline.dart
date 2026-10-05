import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';

/// For things that only work with the server (accusing, buying, ...).
/// Offline: says so kindly, tries the server again in the background, and returns false.
bool needOnline(BuildContext context) {
  if (Api.i.online) return true;
  toast(context, Api.needOnlineText);
  unawaited(Api.i.reconnect());
  return false;
}

/// A small, calm strip shown while the server can't be reached, with a retry.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key, this.margin = EdgeInsets.zero});
  final EdgeInsets margin;

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _busy = false;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    await Api.i.reconnect();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Api.i,
      builder: (context, _) {
        if (Api.i.online) return const SizedBox.shrink();
        return Padding(
          padding: widget.margin,
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 4, 4),
            decoration: BoxDecoration(
              color: K.night3,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: K.brass.withValues(alpha: 0.35)),
            ),
            child: Row(children: [
              const Icon(Icons.wifi_off_rounded, size: 18, color: K.brass),
              const SizedBox(width: 8),
              Expanded(child: Text(Api.offlineBannerText, style: tBody(12.5, color: K.text))),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: K.brass)),
                )
              else
                TextButton(
                  onPressed: _retry,
                  child: Text('دوباره', style: tBody(13, color: K.brass, w: FontWeight.w700)),
                ),
            ]),
          ),
        );
      },
    );
  }
}
