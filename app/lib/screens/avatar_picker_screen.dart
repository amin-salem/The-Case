import 'package:flutter/material.dart';

import '../models/avatars.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/avatar_frame.dart';
import '../widgets/offline.dart';

/// Pick the detective's face and frame. Owned ones are normal, goal ones are dimmed with their goal and a progress
/// bar, shop ones show a price and ask before spending coins.
class AvatarPickerScreen extends StatefulWidget {
  const AvatarPickerScreen({super.key, this.startOnFrames = false});
  final bool startOnFrames;

  @override
  State<AvatarPickerScreen> createState() => _AvatarPickerScreenState();
}

enum _Filter { all, owned, locked }

class _AvatarPickerScreenState extends State<AvatarPickerScreen> {
  AvatarCatalog? _cat;
  bool _failed = false;
  bool _busy = false;
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await Api.i.avatarCatalog();
      if (mounted) setState(() => _cat = c);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _equip(AvatarItem it) async {
    final cat = _cat;
    if (cat == null || _busy || !needOnline(context)) return;
    setState(() => _busy = true);
    try {
      await Api.i.updateProfile(avatarId: it.isFrame ? null : it.id, avatarFrame: it.isFrame ? it.id : null);
      final c = await Api.i.avatarCatalog();
      if (mounted) setState(() => _cat = c);
    } catch (e) {
      if (mounted) toast(context, Api.friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buy(AvatarItem it) async {
    final cat = _cat;
    if (cat == null || _busy || !needOnline(context)) return;
    final enough = cat.coins >= it.price;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: K.paper,
          title: Text(it.title, style: tDisplay(20, color: K.ink)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: AvatarWithFrame(
                  avatar: it.isFrame ? cat.avatar : it.id, frame: it.isFrame ? it.id : cat.frame, size: 110, animate: true),
            ),
            const SizedBox(height: 10),
            if (it.story.isNotEmpty) Text(it.story, style: tBody(13.5, color: K.inkSoft)),
            const SizedBox(height: 8),
            Text(enough ? 'با ${fa(it.price)} سکه می‌خری؟ یک بار می‌خری و برای همیشه مال توئه.' : 'برای این ${fa(it.price)} سکه لازمه و تو ${fa(cat.coins)} سکه داری.',
                style: tBody(14, color: K.ink, w: FontWeight.w700)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('نه، ممنون', style: tBody(14, color: K.inkSoft))),
            if (enough)
              FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: K.stamp),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('بخر', style: tBody(14, color: Colors.white, w: FontWeight.w900))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      _cat = await Api.i.buyAvatarItem(it.id);
      await Api.i.updateProfile(avatarId: it.isFrame ? null : it.id, avatarFrame: it.isFrame ? it.id : null);
      final c = await Api.i.avatarCatalog();
      if (mounted) {
        setState(() => _cat = c);
        toast(context, 'مال تو شد و گذاشتمش');
      }
    } catch (e) {
      if (mounted) toast(context, Api.friendly(e));
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showGoal(AvatarItem it) {
    final cat = _cat;
    if (cat == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: K.night2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Opacity(
              opacity: 0.55,
              child: AvatarWithFrame(
                  avatar: it.isFrame ? cat.avatar : it.id, frame: it.isFrame ? it.id : cat.frame, size: 110),
            ),
            const SizedBox(height: 10),
            Text(it.title, style: tDisplay(19)),
            if (it.story.isNotEmpty) Text(it.story, textAlign: TextAlign.center, style: tBody(13, color: K.textSoft)),
            const SizedBox(height: 12),
            Text('🔒 ${it.goal}', textAlign: TextAlign.center, style: tBody(15, w: FontWeight.w900)),
            const SizedBox(height: 8),
            _Bar(it.fraction),
            const SizedBox(height: 4),
            Text('${fa(it.progress)} از ${fa(it.target)}', style: tBody(13, color: K.textSoft)),
          ]),
        ),
      ),
    );
  }

  void _tap(AvatarItem it, AvatarCatalog cat) {
    final equipped = it.isFrame ? cat.frame == it.id : cat.avatar == it.id;
    if (it.owned) {
      if (!equipped) _equip(it);
    } else if (it.isShop) {
      _buy(it);
    } else {
      _showGoal(it);
    }
  }

  List<AvatarItem> _visible(List<AvatarItem> all) => switch (_filter) {
        _Filter.all => all,
        _Filter.owned => [for (final a in all) if (a.owned) a],
        _Filter.locked => [for (final a in all) if (!a.owned) a],
      };

  @override
  Widget build(BuildContext context) {
    final cat = _cat;
    return DefaultTabController(
      length: 2,
      initialIndex: widget.startOnFrames ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: K.night,
          title: Text('چهره و قاب', style: tDisplay(20)),
          actions: [
            if (cat != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 14),
                child: Center(child: _CoinChip(cat.coins)),
              ),
          ],
          bottom: TabBar(
            indicatorColor: K.brass,
            labelColor: K.brass,
            unselectedLabelColor: K.textSoft,
            labelStyle: tBody(14, w: FontWeight.w900),
            tabs: const [Tab(text: 'چهره‌ها'), Tab(text: 'قاب‌ها')],
          ),
        ),
        body: cat == null
            ? Center(
                child: _failed
                    ? Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(Api.needOnlineText, style: tBody(14, color: K.textSoft)),
                        TextButton(
                            onPressed: () {
                              setState(() => _failed = false);
                              _load();
                            },
                            child: Text('دوباره', style: tBody(14, color: K.brass))),
                      ])
                    : const CircularProgressIndicator(color: K.brass))
            : Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    AvatarWithFrame(avatar: cat.avatar, frame: cat.frame, size: 96, animate: true),
                    const SizedBox(width: 18),
                    Wrap(spacing: 6, children: [
                      for (final (f, label) in const [(_Filter.all, 'همه'), (_Filter.owned, 'باز‌شده'), (_Filter.locked, 'قفل‌دار')])
                        ChoiceChip(
                          label: Text(label, style: tBody(13, color: _filter == f ? K.ink : K.text, w: FontWeight.w700)),
                          selected: _filter == f,
                          selectedColor: K.brass,
                          backgroundColor: K.night3,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                    ]),
                  ]),
                ),
                Expanded(
                  child: TabBarView(children: [
                    _grid(_visible(cat.avatars), cat),
                    _grid(_visible(cat.frames), cat),
                  ]),
                ),
              ]),
      ),
    );
  }

  Widget _grid(List<AvatarItem> items, AvatarCatalog cat) {
    if (items.isEmpty) {
      return Center(child: Text('اینجا چیزی نیست', style: tBody(14, color: K.textSoft)));
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.66),
      itemCount: items.length,
      itemBuilder: (_, i) => _Card(item: items[i], cat: cat, onTap: () => _tap(items[i], cat)),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.item, required this.cat, required this.onTap});
  final AvatarItem item;
  final AvatarCatalog cat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final it = item;
    final equipped = it.isFrame ? cat.frame == it.id : cat.avatar == it.id;
    // a frame is shown on the player's own face, an avatar alone (so the grid stays calm)
    final art = AvatarWithFrame(
        avatar: it.isFrame ? cat.avatar : it.id, frame: it.isFrame ? it.id : (it.legendary ? 'frame_brass' : null), size: 82);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
        decoration: BoxDecoration(
          color: K.night2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: equipped ? K.brass : (it.legendary ? K.kraftDark : K.night3), width: equipped ? 2.5 : 1.5),
        ),
        child: Column(children: [
          SizedBox(
            width: 82,
            height: 82,
            child: Stack(alignment: Alignment.center, children: [
              Opacity(opacity: it.owned ? 1 : 0.4, child: art),
              if (!it.owned) const Icon(Icons.lock_rounded, color: K.text, size: 24),
            ]),
          ),
          const SizedBox(height: 4),
          Text(it.title, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: tBody(11.5, w: FontWeight.w900).copyWith(height: 1.35)),
          const Spacer(),
          if (it.owned)
            Text(equipped ? 'انتخاب‌شده' : (it.how == 'free' ? 'رایگان' : 'مال توئه'),
                style: tBody(11, color: equipped ? K.brass : K.textSoft, w: FontWeight.w700))
          else if (it.isShop)
            _CoinChip(it.price, small: true)
          else ...[
            _Bar(it.fraction),
            const SizedBox(height: 2),
            Text('${fa(it.progress)} از ${fa(it.target)}', style: tBody(10.5, color: K.textSoft)),
          ],
        ]),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar(this.value);
  final double value;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(value: value, minHeight: 6, backgroundColor: K.night3, color: K.brass),
      );
}

class _CoinChip extends StatelessWidget {
  const _CoinChip(this.amount, {this.small = false});
  final int amount;
  final bool small;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: small ? 8 : 10, vertical: small ? 2 : 4),
        decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.monetization_on_rounded, color: K.brass, size: small ? 14 : 18),
          const SizedBox(width: 4),
          Text(fa(amount), style: tBody(small ? 12 : 14, color: K.brass, w: FontWeight.w900)),
        ]),
      );
}
