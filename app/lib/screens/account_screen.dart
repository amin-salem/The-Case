import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../models/progress.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/name_sheet.dart';
import '../widgets/profile_bell.dart';
import '../widgets/id_card.dart';
import '../widgets/offline.dart';
import '../widgets/rank.dart';
import '../widgets/state_view.dart';
import 'account_sheets.dart';
import 'achievements_screen.dart';
import 'avatar_picker_screen.dart';
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
  ReferralStatus? _ref;
  PlayerCard? _card; // own server card: number, joined date, fastest solve (null offline: the card shows dashes)
  final GlobalKey _cardKey = GlobalKey();
  bool _back = false;

  @override
  void initState() {
    super.initState();
    _loadAchievements();
    _loadReferral();
    _loadCard();
  }

  Future<void> _loadCard() async {
    final id = Api.i.profile?.playerId ?? '';
    if (id.isEmpty) return;
    try {
      final c = await Api.i.playerCard(id);
      if (mounted) setState(() => _card = c);
    } catch (_) {
      // offline: number, date and fastest solve stay empty
    }
  }

  Future<void> _shareCard(Profile p) async {
    final theirs = Api.i.inviteNewPlayer;
    final ok = await shareCardImage(
        _cardKey, 'کارت کارآگاهی من در «پرونده» 🕵️ با کد دعوتم ${fa(theirs)} سکه هدیه بگیر: ${p.inviteCode}\n${Api.i.shareUrl}');
    if (!ok && mounted) toast(context, 'عکس کارت ساخته نشد؛ دوباره امتحان کن');
  }

  Future<void> _loadReferral() async {
    final r = await Api.i.referralStatus();
    if (mounted && r != null) setState(() => _ref = r);
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
    await showNameSheet(context);
  }

  Future<void> _pickAvatar() async {
    if (!needOnline(context)) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AvatarPickerScreen()));
  }

  void _showRanks(Profile p) => showNoirSheet<void>(context, child: RankLadder(profile: p));

  void _openSettings() =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: K.night,
        leadingWidth: 64,
        leading: const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Center(child: ProfileBell(size: 34))),
        title: Text('کارت من', style: tDisplay(20)),
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
              Future<void> retry() async {
                await Api.i.reconnect();
              }

              return Api.i.online
                  ? StateView.error(key: const ValueKey('profile-state'), onRetry: retry)
                  : StateView.offline(key: const ValueKey('profile-state'), onRetry: retry);
            }
            // SafeArea: the last card must not end up under the phone's navigation bar
            return SafeArea(
              top: false,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
                const OfflineBanner(margin: EdgeInsets.only(bottom: 12)),
                _cardBlock(p),
                if (!p.secured) ...[const SizedBox(height: 16), _guestStrip()],
                const SizedBox(height: 20),
                _ladder(p),
                const SizedBox(height: 20),
                _rows(p),
              ]),
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- card

  Widget _cardBlock(Profile p) {
    final look = LeagueLook.of(leagueOfRank(p.rank));
    final icon = IconButton(
      key: const ValueKey('card-share'),
      tooltip: 'اشتراک‌گذاری کارت',
      onPressed: () => _shareCard(p),
      icon: Icon(Icons.ios_share_rounded, color: look.accent, size: 22),
    );
    return Column(children: [
      IdCard(key: ValueKey('mycard-${_card?.memberNo ?? 0}'), data: IdCardData.mine(p, _card), boundaryKey: _cardKey, onFlip: (b) => setState(() => _back = b)),
      const SizedBox(height: 6),
      Row(children: [
        IconButton(
          key: const ValueKey('card-name'),
          tooltip: 'تغییر نام',
          onPressed: _editName,
          icon: const Icon(Icons.edit_rounded, color: K.textSoft, size: 20),
        ),
        Expanded(child: Center(child: CardDots(back: _back, look: look))),
        icon,
      ]),
    ]);
  }

  /// Eight shields: the one he stands on is large and lit, the ones behind him are in colour, the ones ahead are grey.
  Widget _ladder(Profile p) {
    final cur = leagueOfRank(p.rank);
    final next = p.nextRankXp;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showRanks(p),
      child: Column(children: [
        SizedBox(
          height: 84,
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (var i = 0; i < kLeagueNames.length; i++) _shield(i, cur),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Text(p.rankTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(14, w: FontWeight.w900, color: K.brass))),
          Text(next == null ? 'بالاترین درجه' : '${fa((next - p.xp).clamp(0, next))} تا ${p.nextRankTitle ?? 'درجه‌ی بعد'}',
              maxLines: 1, style: tBody(12, color: K.textSoft)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: p.rankProgress),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 4, backgroundColor: K.night3, color: K.brass),
          ),
        ),
      ]),
    );
  }

  Widget _shield(int i, int cur) {
    final look = LeagueLook.of(i);
    final size = i == cur ? 62.0 : 34.0;
    Widget img = Image.asset(look.shield, width: size, height: size, fit: BoxFit.contain);
    if (i > cur) {
      img = Opacity(opacity: 0.4, child: ColorFiltered(colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.saturation), child: img));
    } else if (i == cur) {
      img = DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: look.glow.withValues(alpha: 0.55), blurRadius: 24)]),
        child: img,
      );
    }
    return Semantics(label: kLeagueNames[i], child: img);
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

  // ---------------------------------------------------------------- achievements

  /// The 4 most recent badges earned, then the next locked ones.
  /// The newest earned badge (title), for the line under «دستاوردها».
  String? _latestAchievement() {
    final l = _ach;
    if (l == null) return null;
    AchievementRow? best;
    for (final a in l.items) {
      if (!a.earned) continue;
      if (best == null || (a.earnedAt?.millisecondsSinceEpoch ?? 0) > (best.earnedAt?.millisecondsSinceEpoch ?? 0)) best = a;
    }
    return best?.title;
  }

  /// Three quiet rows under the ladder: achievements, the wardrobe, inviting. Each one tap.
  Widget _rows(Profile p) {
    final l = _ach;
    final earned = l?.earned ?? p.achievements;
    final latest = _latestAchievement();
    Widget row({required Key key, required Widget lead, required String title, required String sub, required VoidCallback onTap, bool last = false}) => InkWell(
          key: key,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: Color(0x0DFFFFFF)))),
            child: Row(children: [
              lead,
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, style: tBody(14.5, w: FontWeight.w900, color: K.text)),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(11.5, w: FontWeight.w700, color: const Color(0xFF9C998F))),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF8E8B82)),
            ]),
          ),
        );
    Widget stack(List<String> assets, double size, double overlap) => SizedBox(
          height: size,
          width: size + (assets.length - 1) * (size - overlap),
          child: Stack(children: [
            for (var i = 0; i < assets.length; i++)
              PositionedDirectional(start: i * (size - overlap), child: Image.asset(assets[i], width: size, height: size, fit: BoxFit.contain, errorBuilder: (_, __, ___) => SizedBox(width: size))),
          ]),
        );
    return Container(
      decoration: BoxDecoration(color: const Color(0x09FFFFFF), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0x0FFFFFFF))),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        row(
          key: const ValueKey('row-achievements'),
          lead: stack(const ['assets/medals/medal_gold.webp', 'assets/medals/medal_silver.webp', 'assets/medals/medal_bronze.webp'], 44, 12),
          title: '${fa(earned)} دستاورد',
          sub: latest == null ? 'اولین دستاوردت رو بگیر' : 'آخری: $latest',
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AchievementsScreen())),
        ),
        row(
          key: const ValueKey('row-wardrobe'),
          lead: stack(const ['assets/frames/frame_laurel.webp', 'assets/frames/frame_moon.webp'], 42, 14),
          title: 'کمد کارآگاه',
          sub: 'آواتار و قاب‌ها',
          onTap: _pickAvatar,
        ),
        row(
          key: const ValueKey('row-invite'),
          lead: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: const Color(0x1FE0A526), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.group_add_rounded, color: K.brass, size: 24),
          ),
          title: 'دوستات رو دعوت کن',
          sub: 'کد دعوتت پشت کارته؛ کارت رو بچرخون',
          onTap: () => showNoirSheet<void>(context, child: _inviteSheet(p)),
          last: true,
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- invite

  Widget _rule(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 3), child: Icon(icon, color: K.brass, size: 16)),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: tBody(12.5, color: K.textSoft).copyWith(height: 1.55))),
        ]),
      );

  Widget _bar(int done, int of) => Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
                value: of == 0 ? 0 : (done / of).clamp(0.0, 1.0), minHeight: 8, backgroundColor: K.night3, color: K.brass),
          ),
        ),
        const SizedBox(width: 8),
        Text('${fa(done)} از ${fa(of)} روز', style: tBody(12.5, w: FontWeight.w900, color: K.brass)),
      ]);

  /// The rules and progress of inviting, in a sheet; the code itself is on the back of the card.
  Widget _inviteSheet(Profile p) {
    final code = p.inviteCode;
    final r = _ref;
    final mine = r?.inviterReward ?? Api.i.inviteReward;
    final theirs = r?.newPlayerReward ?? Api.i.inviteNewPlayer;
    final days = r?.needDays ?? 3;
    final canRedeem = r?.canRedeem ?? !p.referred;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.group_add_rounded, color: K.stamp, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text('دوستات رو دعوت کن', style: tDisplay(16.5))),
        ]),
        const SizedBox(height: 4),
        _rule(Icons.redeem_rounded, 'دوستت کدت رو موقع شروع می‌زنه و همون لحظه ${fa(theirs)} سکه می‌گیره.'),
        _rule(Icons.monetization_on_rounded,
            'تو ${fa(mine)} سکه می‌گیری، وقتی اون در ${fa(days)} روز مختلف پرونده حل کنه. جایزه می‌ره تو پیام‌هات؛ بازش کن و بردار.'),
        _rule(Icons.info_outline_rounded, 'حداکثر ${fa(r?.maxPaid ?? 20)} دوست جایزه می‌دن.'),
        const SizedBox(height: 10),
        if (r != null && r.invited > 0) ...[
          if (r.invitedPaid < r.invited && r.bestDays < days) ...[
            Text('نزدیک‌ترین دوستت', style: tBody(12, color: K.textSoft)),
            const SizedBox(height: 4),
            _bar(r.bestDays, days),
            const SizedBox(height: 6),
          ],
          Text('${fa(r.invited)} دوست با کد تو اومدن · جایزه‌ی ${fa(r.invitedPaid)} تاشون رسیده',
              style: tBody(12.5, w: FontWeight.w700)),
          const SizedBox(height: 8),
        ] else if (r != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('هنوز کسی با کد تو نیومده.', style: tBody(12.5, color: K.textSoft)),
          ),
        if (r != null && r.referred) ...[
          Text(r.myInviterPaid ? 'دوستی که دعوتت کرد، جایزه‌ش رو گرفت.' : 'دوستی که دعوتت کرد، جایزه‌ش رو بعد از ${fa(days)} روز حل پرونده می‌گیره:',
              style: tBody(12.5, color: K.textSoft)),
          if (!r.myInviterPaid) ...[const SizedBox(height: 4), _bar(r.myDays, days)],
          const SizedBox(height: 8),
        ],
        StampButton(
          label: 'بفرست برای دوستت',
          height: 46,
          onTap: () => SharePlus.instance.share(ShareParams(
              text: 'بیا «پرونده» بازی کنیم! هر شب یه جنایت تازه 🕵️ موقع شروع کد دعوت من رو بزن تا ${fa(theirs)} سکه هدیه بگیری: $code')),
        ),
        if (canRedeem && !p.referred)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () async {
                await openAccountSheet(context, showInviteCodeSheet);
                _loadReferral();
              },
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
              child: Text('کد دوستت رو داری؟ (تا ۷ روز اول)',
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
