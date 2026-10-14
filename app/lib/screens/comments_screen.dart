import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';

/// What other detectives said about a case: stars, comments, replies. The admin approves everything before it shows.
class CommentsScreen extends StatefulWidget {
  const CommentsScreen({super.key, required this.caseId, required this.title});
  final String caseId;
  final String title;

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  Map<String, dynamic>? _d;
  final List<Map<String, dynamic>> _items = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final before = more && _items.isNotEmpty ? _items.last['id'] as int : 0;
      final d = await Api.i.caseComments(widget.caseId, before: before);
      if (!mounted) return;
      setState(() {
        if (!more) _items.clear();
        _items.addAll((d['items'] as List).cast<Map>().map((e) => e.cast<String, dynamic>()));
        _d = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = !Api.i.online && Api.isNetworkFail(e) ? Api.needOnlineText : Api.friendly(e);
        _loading = false;
      });
    }
  }

  Future<void> _write({int? parentId, String? parentName}) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _WriteSheet(caseId: widget.caseId, parentId: parentId, parentName: parentName),
    );
    if (sent == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final canWrite = d?['can_write'] == true && d?['has_mine'] != true;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: K.night,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title, style: tBody(12, color: K.kraft, w: FontWeight.w700)),
          Text('نظر کارآگاه‌ها', style: tDisplay(19)),
        ]),
      ),
      body: GrainBackground(
        child: SafeArea(
          top: false,
          child: _error != null && _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, textAlign: TextAlign.center, style: tBody(15)),
                      const SizedBox(height: 10),
                      StampButton(label: 'دوباره', onTap: _load),
                    ]),
                  ),
                )
              : d == null
                  ? const Center(child: CircularProgressIndicator(color: K.brass))
                  : Column(children: [
                      Expanded(
                        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                          _summary(d),
                          if (d['mine'] != null) ...[const SizedBox(height: 10), _commentCard(d['mine'] as Map<String, dynamic>, mineBanner: true)],
                          const SizedBox(height: 10),
                          if (_items.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 28),
                              child: Text('هنوز نظری ثبت نشده. اولین کارآگاه باش!',
                                  textAlign: TextAlign.center, style: tBody(14, color: K.textSoft)),
                            ),
                          for (final c in _items) ...[_commentCard(c), const SizedBox(height: 8)],
                          if (d['more'] == true)
                            Center(
                              child: TextButton(
                                onPressed: _loading ? null : () => _load(more: true),
                                child: Text('نظرهای بیشتر', style: tBody(14, color: K.brass, w: FontWeight.w900)),
                              ),
                            ),
                        ]),
                      ),
                      if (canWrite)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                          child: StampButton(label: 'ستاره بده یا نظر بنویس', icon: Icons.edit_rounded, color: K.brass, onTap: _write),
                        )
                      else if (d['can_write'] != true)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                          child: Text('بعد از تموم کردن پرونده می‌تونی نظر بدی',
                              textAlign: TextAlign.center, style: tBody(13, color: K.textSoft)),
                        ),
                    ]),
        ),
      ),
    );
  }

  Widget _summary(Map<String, dynamic> d) {
    final n = d['count'] as int;
    final avg = (d['average'] as num).toDouble();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Column(children: [
          Text(n == 0 ? '—' : '${fa(avg.floor())}٫${fa(((avg - avg.floor()) * 10).round() % 10)}', style: tDisplay(30, color: K.brass)),
          Text('از ۵', style: tBody(11.5, color: K.textSoft)),
        ]),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Stars(n == 0 ? 0 : avg.round()),
            const SizedBox(height: 4),
            Text(n == 0 ? 'هنوز امتیازی نیست' : 'میانگین امتیاز ${fa(n)} کارآگاه', style: tBody(12, color: K.textSoft)),
          ]),
        ),
      ]),
    );
  }

  Widget _commentCard(Map<String, dynamic> c, {bool mineBanner = false}) {
    final replies = (c['replies'] as List).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
    final pending = c['status'] == 'pending';
    final rejected = c['status'] == 'rejected';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: K.night2,
        borderRadius: BorderRadius.circular(14),
        border: mineBanner ? Border.all(color: pending ? K.brass : K.stamp) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (mineBanner)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              pending ? 'نظرت ثبت شد؛ بعد از تأیید مدیر برای همه دیده می‌شود. فقط خودت الان آن را می‌بینی.'
                      : 'نظرت تأیید نشد. می‌توانی آن را بازنویسی کنی.',
              style: tBody(12.5, color: pending ? K.brass : K.stamp, w: FontWeight.w700),
            ),
          ),
        _head(c),
        const SizedBox(height: 4),
        Text(c['body'] as String, style: tBody(13.5)),
        if (c['status'] == 'approved')
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => _write(parentId: c['id'] as int, parentName: c['nickname'] as String),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(0, 32)),
              child: Text('پاسخ', style: tBody(12.5, color: K.kraft, w: FontWeight.w900)),
            ),
          ),
        if (rejected && mineBanner)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: _write,
              child: Text('بازنویسی', style: tBody(13, color: K.brass, w: FontWeight.w900)),
            ),
          ),
        for (final r in replies)
          Container(
            margin: const EdgeInsetsDirectional.only(start: 26, top: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _head(r, reply: true),
              const SizedBox(height: 2),
              Text(r['body'] as String, style: tBody(13)),
            ]),
          ),
      ]),
    );
  }

  Widget _head(Map<String, dynamic> c, {bool reply = false}) {
    final name = c['mine'] == true ? 'تو' : c['nickname'] as String;
    final pending = c['status'] == 'pending';
    return Row(children: [
      Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: K.night3, shape: BoxShape.circle),
        child: Text(name.isEmpty ? '؟' : name.characters.first, style: tBody(13, color: K.brass, w: FontWeight.w900)),
      ),
      const SizedBox(width: 8),
      Flexible(child: Text(name, overflow: TextOverflow.ellipsis, style: tBody(13, w: FontWeight.w900))),
      if (!reply && (c['rating'] as int) > 0) ...[const SizedBox(width: 8), _Stars(c['rating'] as int)],
      if (pending && reply) ...[
        const SizedBox(width: 8),
        Text('در انتظار تأیید', style: tBody(11, color: K.brass, w: FontWeight.w900)),
      ],
    ]);
  }
}

class _Stars extends StatelessWidget {
  const _Stars(this.n);
  final int n;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.ltr, children: [
        for (int i = 1; i <= 5; i++)
          Icon(i <= n ? Icons.star_rounded : Icons.star_border_rounded, color: K.brass, size: 16),
      ]);
}

class _WriteSheet extends StatefulWidget {
  const _WriteSheet({required this.caseId, this.parentId, this.parentName});
  final String caseId;
  final int? parentId;
  final String? parentName;

  @override
  State<_WriteSheet> createState() => _WriteSheetState();
}

class _WriteSheetState extends State<_WriteSheet> {
  final _c = TextEditingController();
  int _rating = 0;
  bool _busy = false;
  String? _err;

  bool get _reply => widget.parentId != null;
  int get _max => _reply ? 200 : 300;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _c.text.trim();
    if (!_reply && _rating == 0) {
      setState(() => _err = 'اول چند ستاره بده');
      return;
    }
    // a root comment may be stars only; a reply, or a text that was started, needs a few letters
    if (text.isNotEmpty || _reply) {
      if (text.length < (_reply ? 2 : 3)) {
        setState(() => _err = 'نظرت خیلی کوتاهه');
        return;
      }
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await Api.i.sendComment(widget.caseId, text, rating: _rating, parentId: widget.parentId);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = Api.friendly(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(22)),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_reply ? 'پاسخ به ${widget.parentName ?? ''}' : 'نظر تو درباره‌ی این پرونده', style: tDisplay(18)),
            if (!_reply) ...[
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.center, textDirection: TextDirection.ltr, children: [
                for (int i = 1; i <= 5; i++)
                  IconButton(
                    onPressed: _busy ? null : () => setState(() => _rating = i),
                    icon: Icon(i <= _rating ? Icons.star_rounded : Icons.star_border_rounded, color: K.brass, size: 38),
                  ),
              ]),
            ],
            const SizedBox(height: 6),
            TextField(
              controller: _c,
              maxLength: _max,
              maxLines: 4,
              minLines: 3,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
              style: tBody(14),
              decoration: InputDecoration(
                hintText: _reply ? 'نظرت را بنویس (قاتل را لو نده!)' : 'نوشتن نظر اختیاریه (قاتل را لو نده!)',
                hintStyle: tBody(13, color: K.textSoft),
                filled: true,
                fillColor: K.night3,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            Text(_reply || _c.text.trim().isNotEmpty ? 'بعد از بررسی مدیر منتشر می‌شود.' : 'ستاره‌ها همان لحظه ثبت می‌شوند.',
                style: tBody(12, color: K.kraft)),
            if (_err != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_err!, style: tBody(12.5, color: K.stamp, w: FontWeight.w700))),
            const SizedBox(height: 12),
            StampButton(
                label: _busy ? 'در حال ارسال…' : (_reply || _c.text.trim().isNotEmpty ? 'ارسال برای بررسی' : 'ثبت ستاره‌ها'),
                color: K.brass,
                onTap: _busy ? null : _send),
          ]),
        ),
      ),
    );
  }
}
