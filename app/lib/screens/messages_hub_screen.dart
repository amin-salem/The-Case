import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/progress.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/badge_cell.dart';
import '../widgets/avatar_frame.dart';
import '../widgets/offline.dart';
import 'achievements_screen.dart';

Future<void> openMessagesHub(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MessagesHubScreen()));

IconData feedIcon(String kind) => switch (kind) {
      'gift' => Icons.card_giftcard_rounded,
      'case' => Icons.folder_special_rounded,
      'weekend' => Icons.nightlight_round,
      'story' => Icons.auto_stories_rounded,
      'badge' => Icons.military_tech_rounded,
      'streak' => Icons.local_fire_department_rounded,
      _ => Icons.campaign_rounded,
    };

/// «امروز» / «دیروز» / «قبل‌تر» for a feed item.
String feedDayLabel(DateTime at, DateTime now) {
  final d = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(d).inDays;
  if (diff <= 0) return 'امروز';
  if (diff == 1) return 'دیروز';
  return 'قبل‌تر';
}

String feedTime(DateTime at) => '${fa(at.hour).padLeft(2, '۰')}:${fa(at.minute).padLeft(2, '۰')}';

/// Messages, notifications and the badge wall in one place.
class MessagesHubScreen extends StatefulWidget {
  const MessagesHubScreen({super.key});

  @override
  State<MessagesHubScreen> createState() => _MessagesHubScreenState();
}

class _MessagesHubScreenState extends State<MessagesHubScreen> {
  Feed? _feed;
  AchievementsList? _ach;
  String? _error;
  int _tab = 0; // 0 messages, 1 badges
  int _filter = 0; // 0 all, 1 gifts, 2 notices
  bool _readAll = false;
  final Set<String> _busy = {};
  Timer? _seenTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _seenTimer?.cancel();
    _inviteTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<Object>([Api.i.feed(), Api.i.achievements()]);
      if (!mounted) return;
      setState(() {
        _feed = results[0] as Feed;
        _ach = results[1] as AchievementsList;
        _error = null;
      });
      _seenTimer?.cancel();
      if ((_feed?.unread ?? 0) > 0) {
        // shown as unread for a moment, then marked seen on the server (the bell goes down)
        _seenTimer = Timer(const Duration(milliseconds: 1500), () => unawaited(Api.i.feedSeen()));
      }
    } catch (e) {
      if (mounted) setState(() => _error = Api.isNetworkFail(e) ? Api.needOnlineText : Api.friendly(e));
    }
  }

  Future<void> _markAll() async {
    if (!needOnline(context)) return;
    await Api.i.feedSeen();
    if (mounted) setState(() => _readAll = true);
  }

  Future<void> _claim(FeedItem it) async {
    if (!needOnline(context) || it.giftId == null) return;
    setState(() => _busy.add(it.id));
    try {
      final coins = await Api.i.claimGift(it.giftId!, it.reward);
      if (mounted) toast(context, coins > 0 ? '${fa(coins)} سکه گرفتی!' : 'دریافت شد!');
    } catch (e) {
      if (mounted) toast(context, Api.friendly(e));
    }
    if (mounted) setState(() => _busy.remove(it.id));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final unreadHere = _readAll ? 0 : (_feed?.items.where((i) => i.unread).length ?? 0);
    return Scaffold(
      appBar: AppBar(backgroundColor: K.night, title: Text('پیام‌ها و نشان‌ها', style: tDisplay(20))),
      body: GrainBackground(
        child: SafeArea(
          top: false,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.25,
            child: RefreshIndicator(
              color: K.stamp,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  const OfflineBanner(margin: EdgeInsets.only(bottom: 10)),
                  _profileCard(),
                  const SizedBox(height: 12),
                  _segmented(unreadHere),
                  const SizedBox(height: 12),
                  if (_feed == null && _ach == null && _error == null)
                    const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: K.brass))),
                  if (_feed == null && _ach == null && _error != null) _errorBox(),
                  if (_tab == 0 && _feed != null) ..._messages(_feed!),
                  if (_tab == 1 && _ach != null) ..._badges(_ach!),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorBox() => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Text(_error!, textAlign: TextAlign.center, style: tBody(14, color: K.textSoft)),
          const SizedBox(height: 12),
          GhostButton(label: 'دوباره', icon: Icons.refresh_rounded, onTap: _load),
        ]),
      );

  // ---------------------------------------------------------------- profile card

  bool _inviteCopied = false;
  Timer? _inviteTimer;

  /// Tap the invite code: copy it, say so in the label for a moment and in a small message.
  Future<void> _copyInvite(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    toast(context, 'کد دعوت کپی شد');
    setState(() => _inviteCopied = true);
    _inviteTimer?.cancel();
    _inviteTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _inviteCopied = false);
    });
  }

  Widget _profileCard() {
    return ListenableBuilder(
      listenable: Api.i,
      builder: (context, _) {
        final p = Api.i.profile;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: K.night2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: K.kraft.withValues(alpha: 0.4)),
          ),
          child: Column(children: [
            Row(children: [
              AvatarWithFrame(avatar: p?.avatarId ?? 'det_01', frame: p?.avatarFrame ?? 'frame_brass', size: 56),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(p?.nickname ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(16, w: FontWeight.w900)),
                  Text(p?.rankTitle ?? '',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(12, color: K.brass, w: FontWeight.w700)),
                ]),
              ),
              if (p != null && p.inviteCode.isNotEmpty)
                Tooltip(
                  message: 'برای کپی بزن',
                  child: Material(
                    color: K.night3,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      key: const ValueKey('hub-invite-code'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _copyInvite(p.inviteCode),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_inviteCopied ? 'کپی شد ✓' : 'کد دعوت',
                              style: tBody(10.5, color: _inviteCopied ? K.brass : K.textSoft).copyWith(height: 1.3)),
                          Text(p.inviteCode, style: tBody(13, w: FontWeight.w900, color: K.brass).copyWith(height: 1.3)),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _stat(Icons.local_fire_department_rounded, fa(p?.streak ?? 0), 'شب پیاپی'),
              _stat(Icons.folder_special_rounded, fa(p?.casesSolved ?? 0), 'پرونده حل‌شده'),
              _stat(Icons.military_tech_rounded, fa(_ach?.earned ?? p?.achievements ?? 0), 'نشان'),
            ]),
          ]),
        );
      },
    );
  }

  Widget _stat(IconData icon, String value, String label) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(12)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              // right to left: the number first, then the icon
              Text(value, style: tBody(15, w: FontWeight.w900).copyWith(height: 1.3)),
              const SizedBox(width: 4),
              Icon(icon, size: 16, color: K.brass),
            ]),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(11, color: K.textSoft).copyWith(height: 1.3)),
          ]),
        ),
      );

  // ---------------------------------------------------------------- tabs

  Widget _segmented(int unreadHere) {
    Widget seg(int i, Widget label) => Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _tab = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _tab == i ? K.paper : Colors.transparent, borderRadius: BorderRadius.circular(11)),
              child: label,
            ),
          ),
        );
    Color c(int i) => _tab == i ? K.ink : K.textSoft;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(14), border: Border.all(color: K.night3)),
      child: Row(children: [
        seg(
          0,
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(
                child: Text('پیام‌ها و اعلان‌ها',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(13, w: FontWeight.w900, color: c(0)).copyWith(height: 1.3))),
            if (unreadHere > 0) ...[
              const SizedBox(width: 6),
              Container(
                key: const ValueKey('hub-unread-pill'),
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(color: K.stamp, borderRadius: BorderRadius.circular(99)),
                child: Text(unreadHere > 99 ? '99+' : fa(unreadHere),
                    textAlign: TextAlign.center, style: tBody(10.5, w: FontWeight.w900, color: K.text).copyWith(height: 1.4)),
              ),
            ],
          ]),
        ),
        seg(1, Text('نشان‌ها', style: tBody(13, w: FontWeight.w900, color: c(1)).copyWith(height: 1.3))),
      ]),
    );
  }

  // ---------------------------------------------------------------- tab 1: messages

  List<Widget> _messages(Feed f) {
    final now = DateTime.now();
    final items = f.items.where((i) => switch (_filter) { 1 => i.isGift, 2 => !i.isGift, _ => true }).toList();
    Widget chip(int i, String label) => Padding(
          padding: const EdgeInsets.only(left: 6),
          child: ChoiceChip(
            label: Text(label, style: tBody(12.5, w: FontWeight.w700, color: _filter == i ? K.ink : K.text).copyWith(height: 1.2)),
            selected: _filter == i,
            onSelected: (_) => setState(() => _filter = i),
            selectedColor: K.paper,
            backgroundColor: K.night2,
            side: const BorderSide(color: K.night3),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
          ),
        );
    final out = <Widget>[
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          chip(0, 'همه'),
          chip(1, 'هدیه‌ها'),
          chip(2, 'اعلان‌ها'),
          ActionChip(
            avatar: const Icon(Icons.done_all_rounded, size: 16, color: K.brass),
            label: Text('خواندن همه', style: tBody(12.5, w: FontWeight.w700, color: K.brass).copyWith(height: 1.2)),
            onPressed: _markAll,
            backgroundColor: K.night2,
            side: BorderSide(color: K.brass.withValues(alpha: 0.5)),
            visualDensity: VisualDensity.compact,
          ),
        ]),
      ),
      const SizedBox(height: 10),
    ];
    if (items.isEmpty) {
      out.add(Padding(
        padding: const EdgeInsets.all(32),
        child: Column(children: [
          const Icon(Icons.mark_email_read_rounded, color: K.textSoft, size: 40),
          const SizedBox(height: 8),
          Text('فعلاً پیام تازه‌ای نداری.', textAlign: TextAlign.center, style: tBody(14, color: K.textSoft)),
        ]),
      ));
      return out;
    }
    String? last;
    for (final it in items) {
      final label = feedDayLabel(it.at, now);
      if (label != last) {
        last = label;
        out.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Text(label, style: tBody(13, color: K.textSoft, w: FontWeight.w900)),
        ));
      }
      out.add(_feedCard(it));
    }
    return out;
  }

  Widget _feedCard(FeedItem it) {
    final unread = it.unread && !_readAll;
    final card = it.isGift ? _giftCard(it, unread) : _noticeCard(it, unread);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: unread || it.claimable ? card : Opacity(opacity: 0.72, child: card),
    );
  }

  Widget _giftCard(FeedItem it, bool unread) {
    return Paper(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.card_giftcard_rounded, color: K.stamp, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.title, style: tBody(15, color: K.ink, w: FontWeight.w900)),
              if (it.body.isNotEmpty) Text(it.body, style: tBody(13, color: K.inkSoft)),
            ]),
          ),
          Text(feedTime(it.at), style: tBody(11, color: K.inkSoft)),
          if (unread) ...[
            const SizedBox(width: 6),
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: K.stamp, shape: BoxShape.circle)),
          ],
        ]),
        const SizedBox(height: 8),
        if (it.claimable)
          StampButton(
            label: it.reward > 0 ? 'دریافت ${fa(it.reward)} سکه' : 'دریافت',
            height: 42,
            onTap: _busy.contains(it.id) ? null : () => _claim(it),
          )
        else
          Row(children: [
            const Icon(Icons.check_circle_rounded, color: K.ok, size: 18),
            const SizedBox(width: 6),
            Text('دریافت شد', style: tBody(12.5, color: K.ink, w: FontWeight.w700)),
          ]),
      ]),
    );
  }

  Widget _noticeCard(FeedItem it, bool unread) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: K.night2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: unread ? K.stamp.withValues(alpha: 0.5) : K.night3),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(10)),
          child: Icon(feedIcon(it.kind), color: K.brass, size: 22),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(it.title, style: tBody(14, w: FontWeight.w900)),
            if (it.body.isNotEmpty) Text(it.body, style: tBody(12.5, color: K.textSoft)),
            if (it.kind == 'badge' && it.reward > 0)
              Text('+${fa(it.reward)} سکه', style: tBody(12, color: K.brass, w: FontWeight.w700)),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(feedTime(it.at), style: tBody(11, color: K.textSoft)),
          if (unread)
            Container(
              margin: const EdgeInsets.only(top: 6),
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: K.stamp, shape: BoxShape.circle),
            ),
        ]),
      ]),
    );
  }

  // ---------------------------------------------------------------- tab 2: badge wall

  List<Widget> _badges(AchievementsList l) {
    final out = <Widget>[
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: K.night2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: K.brass.withValues(alpha: 0.5)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.military_tech_rounded, color: K.brass, size: 30),
            const SizedBox(width: 8),
            Expanded(child: Text('${fa(l.earned)} از ${fa(l.total)} نشان', style: tDisplay(18))),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
                value: l.total == 0 ? 0 : l.earned / l.total, minHeight: 7, backgroundColor: K.night3, color: K.brass),
          ),
        ]),
      ),
    ];
    for (final g in kAchievementGroups.entries) {
      final items = l.items.where((a) => a.group == g.key).toList();
      if (items.isEmpty) continue;
      out.add(const SizedBox(height: 16));
      out.add(Row(children: [
        Icon(g.value.$1, color: K.brass, size: 20),
        const SizedBox(width: 6),
        Expanded(child: Text(g.value.$2, style: tDisplay(16))),
        Text('${fa(items.where((a) => a.earned).length)}/${fa(items.length)}',
            style: tBody(12.5, color: K.textSoft, w: FontWeight.w700)),
      ]));
      out.add(const SizedBox(height: 10));
      out.add(LayoutBuilder(builder: (context, box) {
        final w = (box.maxWidth - 2 * 8) / 3;
        return Wrap(spacing: 8, runSpacing: 14, children: [
          for (final a in items)
            SizedBox(width: w, child: BadgeCell(badge: a, icon: g.value.$1, onTap: () => _badgeSheet(a, g.value.$1))),
        ]);
      }));
    }
    return out;
  }

  void _badgeSheet(AchievementRow a, IconData icon) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: K.night2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: SizedBox(width: 110, child: BadgeCell(badge: a, icon: icon))),
            const SizedBox(height: 10),
            Text(a.title, textAlign: TextAlign.center, style: tDisplay(20)),
            const SizedBox(height: 8),
            Text('چطور به دست میاد', style: tBody(12, color: K.textSoft, w: FontWeight.w700)),
            Text(a.desc, style: tBody(14.5)),
            const SizedBox(height: 8),
            Text('پیشرفت: ${fa(a.progress)} از ${fa(a.target)}', style: tBody(13.5, color: a.earned ? K.ok : K.brass, w: FontWeight.w700)),
            if (a.coins > 0 || a.xp > 0)
              Text('جایزه: ${fa(a.coins)} سکه · ${fa(a.xp)} امتیاز', style: tBody(13, color: K.textSoft)),
            const SizedBox(height: 14),
            GhostButton(label: 'بستن', onTap: () => Navigator.pop(context)),
          ]),
        ),
      ),
    );
  }
}
