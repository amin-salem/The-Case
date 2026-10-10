import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../models/progress.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/character.dart';
import '../widgets/crime_tape.dart';
import '../widgets/offline.dart';
import '../widgets/rank.dart';
import 'account_sheets.dart';
import 'achievements_screen.dart';
import 'settings_screen.dart';

/// The detective's profile: who you are, your numbers, your badges and your invite code.
/// Everything you set (account, font, sound, reminders) lives in [SettingsScreen] behind the ⚙.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  AchievementsList? _ach;

  @override
  void initState() {
    super.initState();
    _loadAchievements();
  }

  Future<void> _loadAchievements() async {
    try {
      final l = await Api.i.achievements();
      if (mounted) setState(() => _ach = l);
    } catch (_) {
      // offline with nothing saved: the card shows the count from the profile only
    }
  }

  Future<void> _editName() async {
    if (!needOnline(context)) return;
    final c = TextEditingController(text: Api.i.profile?.nickname ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: K.paper,
        title: Text('اسم کارآگاه', style: tDisplay(20, color: K.ink)),
        content: TextField(controller: c, maxLength: 16, autofocus: true, style: tBody(16, color: K.ink)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('انصراف', style: tBody(14, color: K.inkSoft))),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: K.stamp), onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: Text('ذخیره', style: tBody(14, color: Colors.white))),
        ],
      ),
    );
    c.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await Api.i.updateProfile(nickname: name);
    } catch (e) {
      if (mounted) toast(context, Api.friendly(e));
    }
  }

  Future<void> _setAvatar(int i) async {
    if (!needOnline(context)) return;
    try {
      await Api.i.updateProfile(avatar: i);
    } catch (e) {
      if (mounted) toast(context, Api.friendly(e));
    }
  }

  Future<void> _pickAvatar() async {
    final current = Api.i.profile?.avatar ?? 0;
    final picked = await showNoirSheet<int>(
      context,
      title: 'چهره‌ی کارآگاه',
      child: Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
        for (int i = 0; i < kDetectives.length; i++)
          Builder(
            builder: (ctx) => GestureDetector(
              onTap: () => Navigator.of(ctx).pop(i),
              child: Container(
                width: 72,
                height: 72,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: K.night3,
                  shape: BoxShape.circle,
                  border: Border.all(color: current == i ? K.brass : Colors.transparent, width: 2.5),
                ),
                child: DetectiveFace(i, size: 60),
              ),
            ),
          ),
      ]),
    );
    if (picked != null && picked != current && mounted) await _setAvatar(picked);
  }

  void _showRanks(Profile p) => showNoirSheet<void>(context, child: RankLadder(profile: p));

  void _openSettings() =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: K.night,
        title: Text('پرونده‌ی شخصی', style: tDisplay(20)),
        actions: [
          IconButton(
            tooltip: 'تنظیمات',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_rounded, color: K.text),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: GrainBackground(
        child: ListenableBuilder(
          listenable: Api.i,
          builder: (context, _) {
            final p = Api.i.profile;
            if (p == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(Api.i.online ? Api.genericText : Api.needOnlineText,
                      textAlign: TextAlign.center, style: tBody(15, color: K.textSoft)),
                ),
              );
            }
            // SafeArea: the last card must not end up under the phone's navigation bar
            return SafeArea(
              top: false,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
                const OfflineBanner(margin: EdgeInsets.only(bottom: 12)),
                _header(p),
                if (!p.secured) ...[const SizedBox(height: 12), _guestStrip()],
                const SizedBox(height: 12),
                Row(children: [
                  _stat('پرونده‌ی حل‌شده', fa(p.casesSolved)),
                  _stat('زنجیره', fa(p.streak), icon: Icons.local_fire_department_rounded, color: K.stamp),
                  _stat('بهترین زنجیره', fa(p.bestStreak)),
                ]),
                const SizedBox(height: 12),
                _achievements(p),
                const SizedBox(height: 12),
                _invite(p),
              ]),
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- header

  Widget _header(Profile p) {
    final next = p.nextRankXp;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: K.night2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: K.brass.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const CrimeTape(height: 18, text: 'پرونده‌ی شخصی  •  محرمانه  •  '),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onTap: _pickAvatar,
              child: SizedBox(
                width: 84,
                height: 84,
                child: Stack(clipBehavior: Clip.none, children: [
                  Container(
                    width: 84,
                    height: 84,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: K.night3, border: Border.all(color: K.brass, width: 2)),
                    child: DetectiveFace(p.avatar, size: 76),
                  ),
                  PositionedDirectional(
                    bottom: -2,
                    end: -2,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(color: K.stamp, shape: BoxShape.circle, border: Border.all(color: K.night2, width: 2.5)),
                      child: const Icon(Icons.edit_rounded, size: 14, color: Colors.white),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _editName,
                  child: Row(children: [
                    Flexible(child: Text(p.nickname, maxLines: 1, style: tDisplay(21), overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 6),
                    const Icon(Icons.edit_rounded, size: 16, color: K.textSoft),
                  ]),
                ),
                if (p.vip)
                  Row(children: [
                    const Icon(Icons.diamond_rounded, size: 15, color: K.brass),
                    const SizedBox(width: 4),
                    Text('کارآگاه ویژه (VIP)', style: tBody(12.5, color: K.brass, w: FontWeight.w900)),
                  ]),
                const SizedBox(height: 6),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _showRanks(p),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      RankIcon(rank: p.rank, size: 22),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(p.rankTitle,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(14, w: FontWeight.w900, color: K.brass)),
                      ),
                      Text('${fa(p.xp)} امتیاز', style: tBody(12, color: K.textSoft)),
                      const Icon(Icons.chevron_left_rounded, size: 18, color: K.textSoft),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: p.rankProgress),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        builder: (_, v, __) =>
                            LinearProgressIndicator(value: v, minHeight: 7, backgroundColor: K.night3, color: K.brass),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      next == null
                          ? 'بالاترین درجه رو داری!'
                          : '${fa((next - p.xp).clamp(0, next))} امتیاز تا ${p.nextRankTitle ?? 'درجه‌ی بعد'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tBody(12, color: K.textSoft),
                    ),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _guestStrip() => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: K.brass.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: K.brass.withValues(alpha: 0.55)),
        ),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: K.brass, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text('حسابت هنوز امن نیست. اگه گوشی عوض بشه، همه‌چی می‌پره.',
                style: tBody(13, color: K.text, w: FontWeight.w700).copyWith(height: 1.55)),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => openAccountSheet(context, showSecureSheet),
            style: FilledButton.styleFrom(
              backgroundColor: K.brass,
              foregroundColor: K.ink,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 38),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('امنش کن', style: tBody(13.5, color: K.ink, w: FontWeight.w900)),
          ),
        ]),
      );

  Widget _stat(String label, String value, {IconData? icon, Color color = K.brass}) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: K.night2,
            borderRadius: BorderRadius.circular(12),
            border: icon == null ? null : Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (icon != null) ...[Icon(icon, color: color, size: 20), const SizedBox(width: 2)],
              Text(value, style: tDisplay(20, color: color)),
            ]),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                style: tBody(11.5, color: K.textSoft)),
          ]),
        ),
      );

  // ---------------------------------------------------------------- achievements

  /// The 4 most recent badges earned, then the next locked ones.
  List<AchievementRow> _shelf(AchievementsList l) {
    final earned = l.items.where((a) => a.earned).toList()
      ..sort((a, b) => (b.earnedAt?.millisecondsSinceEpoch ?? 0).compareTo(a.earnedAt?.millisecondsSinceEpoch ?? 0));
    double frac(AchievementRow a) => a.target == 0 ? 0 : a.progress / a.target;
    final locked = l.items.where((a) => !a.earned).toList()..sort((a, b) => frac(b).compareTo(frac(a)));
    return [...earned.take(4), ...locked].take(4).toList();
  }

  Widget _achievements(Profile p) {
    final l = _ach;
    final count = l == null ? '${fa(p.achievements)} تا' : '${fa(l.earned)} از ${fa(l.total)}';
    final shelf = l == null ? const <AchievementRow>[] : _shelf(l);
    void openAll() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AchievementsScreen()));
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 14),
      decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.military_tech_rounded, color: K.brass, size: 22),
          const SizedBox(width: 6),
          Text('دستاوردها', style: tDisplay(16.5)),
          const SizedBox(width: 10),
          Expanded(child: Text(count, style: tBody(13.5, color: K.textSoft, w: FontWeight.w700))),
          TextButton(
            onPressed: openAll,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('همه', style: tBody(13.5, color: K.brass, w: FontWeight.w900)),
              const Icon(Icons.chevron_left_rounded, color: K.brass, size: 20),
            ]),
          ),
        ]),
        if (shelf.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final a in shelf) Expanded(child: _badge(a, openAll)),
              for (int i = shelf.length; i < 4; i++) const Expanded(child: SizedBox()),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _badge(AchievementRow a, VoidCallback onTap) {
    final icon = kAchievementGroups[a.group]?.$1 ?? Icons.military_tech_rounded;
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: a.earned ? K.brass : K.night3,
            border: Border.all(color: a.earned ? const Color(0xFF9C7420) : K.textSoft.withValues(alpha: 0.3), width: 2),
          ),
          child: Icon(a.earned ? icon : Icons.lock_outline_rounded, color: a.earned ? K.ink : K.textSoft, size: 26),
        ),
        const SizedBox(height: 4),
        Text(a.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: tBody(11.5, color: a.earned ? K.text : K.textSoft, w: FontWeight.w700).copyWith(height: 1.35)),
      ]),
    );
  }

  // ---------------------------------------------------------------- invite

  Widget _invite(Profile p) {
    final code = p.inviteCode;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: K.night2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: K.stamp.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.group_add_rounded, color: K.stamp, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text('دوستات رو دعوت کن', style: tDisplay(16.5))),
        ]),
        const SizedBox(height: 2),
        Text('هر دوستی که با کد تو بیاد، ${fa(Api.i.inviteReward)} سکه می‌گیری و دوستت ${fa(Api.i.inviteNewPlayer)} سکه.',
            style: tBody(12.5, color: K.textSoft)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Container(
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: K.night,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: K.brass.withValues(alpha: 0.5)),
              ),
              child: SelectableText(code, textDirection: TextDirection.ltr, style: tDisplay(22, color: K.brass)),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 112,
            child: StampButton(
              label: 'بفرست',
              height: 46,
              onTap: () => SharePlus.instance.share(ShareParams(
                  text: 'بیا «پرونده» بازی کنیم! هر شب یه جنایت تازه 🕵️ موقع شروع کد دعوت من رو بزن: $code')),
            ),
          ),
        ]),
        if (!p.referred)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => openAccountSheet(context, showInviteCodeSheet),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
              child: Text('کد دوستت رو داری؟',
                  style: tBody(13, color: K.textSoft, w: FontWeight.w700)
                      .copyWith(decoration: TextDecoration.underline, decorationColor: K.textSoft)),
            ),
          )
        else
          const SizedBox(height: 6),
      ]),
    );
  }
}
