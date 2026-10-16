import 'package:flutter/material.dart';

import '../screens/comments_screen.dart';
import '../services/api.dart';
import '../theme.dart';

/// "۴٫۲" for 4.2.
String faRating(double v) {
  final t = (v * 10).round();
  return '${fa(t ~/ 10)}٫${fa(t % 10)}';
}

/// Average stars and the number of comments on a case card: «★ ۴٫۲ (۱۲)  💬 ۳». Nothing is drawn while nobody rated.
class RatingChip extends StatelessWidget {
  const RatingChip({super.key, required this.avg, required this.count, this.comments = 0, this.size = 12});
  final double avg;
  final int count;
  final int comments;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.favorite_rounded, color: K.stamp, size: size + 3),
      const SizedBox(width: 2),
      Text(faRating(avg), style: tBody(size, w: FontWeight.w900, color: K.brass).copyWith(height: 1.2)),
      Text(' (${fa(count)})', style: tBody(size - 1, color: K.textSoft).copyWith(height: 1.2)),
      if (comments > 0) ...[
        const SizedBox(width: 8),
        Icon(Icons.chat_bubble_outline_rounded, color: K.textSoft, size: size + 1),
        const SizedBox(width: 2),
        Text(fa(comments), style: tBody(size - 1, color: K.textSoft).copyWith(height: 1.2)),
      ],
    ]);
  }
}

/// The rating step on a finished case (result screen, an opened solved or archived case):
/// five big stars, ONE tap rates (counted at once), then an optional sentence. «بعداً» closes it in one tap.
/// Without a rating yet it asks; with one it shows the average and the way to the comments.
class RateCard extends StatefulWidget {
  const RateCard({super.key, required this.caseId, required this.title});
  final String caseId;
  final String title;

  @override
  State<RateCard> createState() => _RateCardState();
}

class _RateCardState extends State<RateCard> {
  Map<String, dynamic>? _d;
  bool _failed = false;
  bool _hasMine = false;
  int _stars = 0;
  bool _busy = false;
  bool _textOpen = false;
  bool _textSent = false;
  String? _err;
  late bool _skipped = Api.i.flag('rate_skip_${widget.caseId}');
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await Api.i.caseComments(widget.caseId);
      if (!mounted) return;
      setState(() {
        _d = d;
        _hasMine = d['has_mine'] == true;
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _openComments() => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => CommentsScreen(caseId: widget.caseId, title: widget.title)))
      .then((_) => _load());

  Future<void> _rate(int stars) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _stars = stars;
      _err = null;
    });
    try {
      await Api.i.sendComment(widget.caseId, '', rating: stars);
      if (!mounted) return;
      setState(() => _hasMine = true);
      _load();
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.code == 'already_commented') {
        setState(() => _hasMine = true);
      } else {
        setState(() => _err = Api.friendly(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendText() async {
    final t = _text.text.trim();
    if (t.length < 3) {
      setState(() => _err = 'نظرت خیلی کوتاهه');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await Api.i.sendComment(widget.caseId, t, rating: _stars > 0 ? _stars : 5); // the server keeps the stars already given
      if (mounted) {
        setState(() {
          _textSent = true;
          _textOpen = false;
        });
        _load();
      }
    } catch (e) {
      if (mounted) setState(() => _err = Api.friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _skip(bool on) {
    Api.i.setFlag('rate_skip_${widget.caseId}', on);
    setState(() => _skipped = on);
  }

  BoxDecoration get _box => BoxDecoration(
        color: K.night2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: K.brass.withValues(alpha: 0.6), width: 1.5),
      );

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (_failed || d == null) {
      // offline or still loading: the way to the comments stays one tap away
      if (!_failed) return const SizedBox.shrink();
      return GhostButton(label: 'نظر کارآگاه‌ها', icon: Icons.chat_bubble_outline_rounded, onTap: _openComments);
    }
    final count = (d['count'] as num?)?.toInt() ?? 0;
    final avg = (d['average'] as num?)?.toDouble() ?? 0;
    final canWrite = d['can_write'] == true;
    final summary = count == 0 ? 'هنوز امتیازی نیست؛ اولین نفر باش' : 'میانگین ${faRating(avg)} از ۵ · ${fa(count)} کارآگاه';

    if (!_hasMine && canWrite && !_skipped) return _ask(summary);
    return _done(summary, canWrite);
  }

  /// Not rated yet: big stars, a close button.
  Widget _ask(String summary) => Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
        decoration: _box,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('این پرونده چطور بود؟', style: tDisplay(17.5))),
            TextButton(
              onPressed: _busy ? null : () => _skip(true),
              style: TextButton.styleFrom(minimumSize: const Size(48, 40), foregroundColor: K.textSoft),
              child: Text('بعداً', style: tBody(13, color: K.textSoft, w: FontWeight.w700)),
            ),
          ]),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: Text('یه ضربه کافیه؛ به کارآگاه‌های بعدی کمک می‌کنی. $summary',
                style: tBody(12.5, color: K.textSoft)),
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.center, textDirection: TextDirection.ltr, children: [
            for (int i = 1; i <= 5; i++)
              IconButton(
                onPressed: _busy ? null : () => _rate(i),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
                icon: Icon(i <= _stars ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: K.stamp, size: 42),
              ),
          ]),
          if (_err != null) Text(_err!, textAlign: TextAlign.center, style: tBody(12.5, color: K.stamp, w: FontWeight.w700)),
        ]),
      );

  /// Rated (or skipped, or not allowed to rate): the average, the comments, and the optional sentence.
  Widget _done(String summary, bool canWrite) {
    final rated = _hasMine;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: _box.copyWith(border: Border.all(color: K.night3)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(rated ? Icons.check_circle_rounded : Icons.favorite_rounded, color: rated ? K.ok : K.stamp, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(rated ? (_textSent ? 'ممنون! نظرت بعد از تأیید مدیر نمایش داده می‌شه.' : 'ممنون! امتیازت ثبت شد.') : 'امتیاز کارآگاه‌ها',
                  style: tBody(14, w: FontWeight.w900)),
              Text(summary, style: tBody(12, color: K.textSoft)),
            ]),
          ),
          TextButton(
            onPressed: _openComments,
            child: Text('نظرها', style: tBody(13.5, color: K.brass, w: FontWeight.w900)),
          ),
        ]),
        if (!rated && canWrite && _skipped)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => _skip(false),
              icon: const Icon(Icons.favorite_border_rounded, color: K.stamp, size: 20),
              label: Text('امتیاز بده', style: tBody(13.5, color: K.brass, w: FontWeight.w900)),
            ),
          ),
        if (rated && !_textSent && !_hasText && !_textOpen)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() => _textOpen = true),
              icon: const Icon(Icons.edit_rounded, color: K.textSoft, size: 18),
              label: Text('یه جمله هم بنویس (اختیاری)', style: tBody(13, color: K.textSoft, w: FontWeight.w700)),
            ),
          ),
        if (_textOpen) ...[
          const SizedBox(height: 4),
          TextField(
            controller: _text,
            maxLength: 300,
            maxLines: 3,
            minLines: 2,
            enabled: !_busy,
            style: tBody(14),
            decoration: InputDecoration(
              hintText: 'نظرت رو بنویس (قاتل رو لو نده!)',
              hintStyle: tBody(13, color: K.textSoft),
              filled: true,
              fillColor: K.night3,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          Row(children: [
            Expanded(child: StampButton(label: _busy ? 'در حال ارسال…' : 'ارسال', height: 44, color: K.brass, onTap: _busy ? null : _sendText)),
            const SizedBox(width: 8),
            TextButton(
                onPressed: _busy ? null : () => setState(() => _textOpen = false),
                child: Text('بعداً', style: tBody(13, color: K.textSoft, w: FontWeight.w700))),
          ]),
        ],
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_err!, style: tBody(12.5, color: K.stamp, w: FontWeight.w700))),
      ]),
    );
  }

  /// The player already wrote words (a pending or approved comment): no second invitation.
  bool get _hasText {
    final m = _d?['mine'];
    if (m is Map && (m['body'] as String? ?? '').isNotEmpty) return true;
    final items = _d?['items'];
    return items is List && items.any((e) => e is Map && e['mine'] == true);
  }
}
