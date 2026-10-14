import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/cast_strip.dart';
import '../widgets/character.dart';
import 'case_screen.dart';
import 'suspect_sheet.dart';

/// Local flag (Api.flag): the weekend tutorial was shown (or skipped) once on this phone.
const kWeekendTutorialFlag = 'weekend_tutorial_seen_v1';

/// What opens after the tutorial (tests replace it so no server is needed).
@visibleForTesting
Widget Function(String caseId) weekendCaseBuilder = (id) => CaseScreen(caseId: id);

/// Opens a weekend case. The first time on this phone the short practice tutorial comes first.
Future<void> openWeekendCase(BuildContext context, String caseId) async {
  if (!Api.i.flag(kWeekendTutorialFlag)) {
    await WeekendTutorial.show(context);
    if (!context.mounted) return;
  }
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => weekendCaseBuilder(caseId)));
}

/// The «راهنما» button of the weekend hub and the weekend case: replays the tutorial any time.
class WeekendHelpButton extends StatelessWidget {
  const WeekendHelpButton({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        tooltip: 'راهنما',
        visualDensity: VisualDensity.compact,
        onPressed: () => WeekendTutorial.show(context),
        icon: const Icon(Icons.help_outline_rounded, color: K.brass),
      );
    }
    return TextButton.icon(
      onPressed: () => WeekendTutorial.show(context),
      icon: const Icon(Icons.help_outline_rounded, color: K.brass, size: 20),
      label: Text('راهنما', style: tBody(13, color: K.brass, w: FontWeight.w700)),
    );
  }
}

// ---------------------------------------------------------------- the practice case (built into the app)

Map<String, dynamic> _avatar(String gender, String age, int skin, String hair, String color, String outfit,
        {String beard = 'none', bool glasses = false}) =>
    {'gender': gender, 'age': age, 'skin': skin, 'hair': hair, 'hairColor': color, 'outfit': outfit, 'beard': beard, 'glasses': glasses};

/// A tiny made-up case: nothing to do with a real one (no spoilers). Culprit: s2.
CaseData practiceCase() => CaseData({
      'id': 'practice',
      'title': 'گلدانِ شکسته',
      'location': 'موزه‌ی کوچک · پرونده‌ی تمرینی',
      'scene': 'office',
      'format': 2,
      'shows_per_chapter': 3,
      'chapters_total': 2,
      'intro': 'ظهر، گلدان قدیمیِ سالن موزه شکسته. در پشتی باز مونده و کنارش یه تکه گِل افتاده. سه مظنون اون اطراف بودن.',
      'suspects': [
        {
          'id': 's1',
          'name': 'سارا نیکو',
          'role': 'نگهبان',
          'age': 34,
          'avatar': _avatar('f', 'mid', 1, 'bob', '#2a2a2a', '#3b4a5e'),
          'motive': 'ندارد؛ فقط مسئول سالن بود.',
          'statement': 'من پشت میز نگهبانی بودم و صدایی نشنیدم.',
          'questions': [
            {'q': 'ظهر کجا بودی؟', 'a': 'سر پستم. همه می‌تونن تأیید کنن.'}
          ],
        },
        {
          'id': 's2',
          'name': 'کامران رضایی',
          'role': 'باغبان',
          'age': 45,
          'avatar': _avatar('m', 'mid', 2, 'short', '#4a3b2a', '#5a6b3e', beard: 'stubble'),
          'motive': 'پول لازم داشت.',
          'statement': 'من تو باغ بودم. به سالن اصلاً نیومدم.',
          'questions': [
            {'q': 'کفشت چرا گِلیه؟', 'a': 'باغبونم دیگه؛ گِل جزو کارمه.'}
          ],
        },
        {
          'id': 's3',
          'name': 'مهسا کریمی',
          'role': 'راهنمای موزه',
          'age': 28,
          'avatar': _avatar('f', 'young', 1, 'long', '#5a3a2a', '#8a4b4b', glasses: true),
          'motive': 'از نگهبان دلخور بود.',
          'statement': 'داشتم برای یه گروه توضیح می‌دادم. بعدش صدای شکستن اومد.',
          'questions': [
            {'q': 'چی دیدی؟', 'a': 'فقط تکه‌های گلدون رو دیدم، کسی اونجا نبود.'}
          ],
        },
      ],
      'evidence': [
        {'id': 'e1', 'type': 'object', 'title': 'گِل کنار در پشتی', 'text': 'یه ردِ گِلی از در پشتی تا کنار گلدون.'},
        {'id': 'e2', 'type': 'cctv', 'title': 'دوربین راهرو', 'text': 'ساعت ۱۲:۰۵ یه سایه با کیف بزرگ از راهرو رد می‌شه.'},
        {'id': 'e3', 'type': 'receipt', 'title': 'فاکتور گلدان', 'text': 'یه فاکتور فروش برای گلدونِ مشابه.'},
        {'id': 'e4', 'type': 'object', 'title': 'دستکش گِلی', 'text': 'یه جفت دستکش گِلی تو انباری.'},
      ],
      'motives': [
        {'id': 'm1', 'text': 'از روی حسادت، تا موزه بی‌آبرو بشه'},
        {'id': 'm2', 'text': 'می‌خواست گلدان رو بدزده؛ موقع فرار از دستش افتاد'},
        {'id': 'm3', 'text': 'تصادفی به میز خورد و ترسید'},
      ],
    });

const String _culprit = 's2';
const String _rightWhy = 'm2';
const String _slipEvidence = 'e1';

const _neutral = {
  's1': 'من؟ تمام روز پشت میز بودم. به من ربطی نداره.',
  's2': 'این؟ نمی‌دونم. من که چیزی ندیدم.',
  's3': 'والا چی بگم؛ من فقط داشتم توضیح می‌دادم.',
};
const _slipLine = 'گِل؟ ... من که از در پشتی رد نشدم... یعنی... هیچی، هیچی!';

// ---------------------------------------------------------------- the tutorial

/// A 90-second interactive practice on a built-in fake case. Local only: no server call, no coins, no stars,
/// no rewards, nothing stored (the seen flag is set by [openWeekendCase] / [show]'s caller path).
class WeekendTutorial extends StatefulWidget {
  const WeekendTutorial({super.key});

  /// Plays the tutorial and marks it as seen when it closes (finished, skipped or backed out).
  static Future<void> show(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WeekendTutorial()));
    await Api.i.setFlag(kWeekendTutorialFlag);
  }

  @override
  State<WeekendTutorial> createState() => _WeekendTutorialState();
}

enum _Phase { board, accuse, done }

class _WeekendTutorialState extends State<WeekendTutorial> {
  final CaseData _case = practiceCase();
  _Phase _phase = _Phase.board;
  int _step = 0; // 0 chapters, 1 early accuse, 2 show a card, 3 slip, 4 accuse, 5 archive + go
  int _left = 3;
  bool _slip = false;
  final List<ShowNote> _shows = [];
  final Map<String, SuspectMark> _marks = {};
  Duration _countdown = const Duration(hours: 24);
  Timer? _timer;

  // practice accusation
  int _accuseStage = 0; // 0 who, 1 why
  String? _pickSuspect, _pickWhy;
  final Set<String> _badSuspects = {}, _badWhys = {};
  String? _accuseNote;
  int _tries = 3;

  // the coach text shown inside the suspect sheet
  final ValueNotifier<String> _sheetNote = ValueNotifier('یه مدرک انتخاب کن و نشونش بده؛ بعد واکنشش رو بخون.');
  final ValueNotifier<int> _leftN = ValueNotifier(3);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _countdown = _countdown - const Duration(seconds: 1));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sheetNote.dispose();
    _leftN.dispose();
    super.dispose();
  }

  void _close() {
    if (mounted) Navigator.of(context).pop();
  }

  void _hint(String msg) => toast(context, msg);

  // ------------------------------------------------ step texts

  String get _coachText => switch (_step) {
        0 => 'این پرونده دو فصل داره. فصل ۱ الان بازه، فصل ۲ دقیقاً ۲۴ ساعت بعد باز می‌شه و مدرک تازه می‌آره. روی فصل ۲ بزن.',
        1 =>
          'از همین فصل ۱ می‌تونی متهم کنی. اگه همون اول درست حدس بزنی، ${fa(Api.i.weeklyEarlyBonus)} سکه‌ی اضافه می‌گیری. روی «متهم کردن» بزن.',
        2 => 'حالا یه مظنون رو بزن، بعد یه مدرک نشونش بده و ببین چی می‌گه. هر فصل فقط ۳ بار می‌تونی نشون بدی.',
        3 => _slip
            ? 'لو رفت! به این می‌گن «لغزش»: حرفی که نباید می‌دونست. لغزش یه سرنخه. مظنون رو ببند و ادامه بده.'
            : 'این واکنش عادی بود. واکنش عادی یعنی سرنخی نیست. یه مدرک یا مظنون دیگه رو امتحان کن تا لغزش پیدا کنی.',
        4 => _phase == _Phase.board
            ? 'وقتشه! روی «متهم کردن» بزن. اول می‌گی «چه کسی؟»، بعد «چرا و چطور؟».'
            : (_accuseStage == 0
                ? 'قدم اول: چه کسی؟ اگه اشتباه بگی، یه فرصتت می‌سوزه.'
                : 'قدم دوم: چرا و چطور؟ ۳ ستاره فقط وقتی می‌گیری که هر دو قدم درست باشه.'),
        _ => 'بعد از ۴۸ ساعت پرونده بسته می‌شه؛ ولی بعدش می‌تونی از بایگانی و با پرداخت سکه بازش کنی. آماده‌ای؟',
      };

  // ------------------------------------------------ actions

  void _tapChapter2() {
    if (_step == 0) {
      setState(() => _step = 1);
    } else {
      _hint('فصل ۲ بعد از ۲۴ ساعت باز می‌شه');
    }
  }

  void _tapAccuse() {
    if (_step == 1) {
      setState(() => _step = 2);
    } else if (_step >= 4) {
      setState(() {
        _phase = _Phase.accuse;
        _accuseStage = 0;
        _accuseNote = null;
      });
    } else {
      _hint('اول مرحله‌ی بالا رو انجام بده');
    }
  }

  Future<({String text, int left})> _localShow(String suspectId, String evidenceId) async {
    final repeated = _shows.any((x) => x.suspect == suspectId && x.evidence == evidenceId);
    final slip = suspectId == _culprit && evidenceId == _slipEvidence;
    final text = slip ? _slipLine : (_neutral[suspectId] ?? 'نمی‌دونم.');
    if (!repeated) {
      _shows.add(ShowNote(suspect: suspectId, evidence: evidenceId, text: text));
      _left = _left - 1;
    }
    if (!slip && _left <= 0) _left = 3; // practice: never get stuck without a slip
    _leftN.value = _left;
    if (slip) _slip = true;
    _sheetNote.value = slip
        ? 'لو رفت! «لغزش» یعنی حرفی که نباید می‌دونست. لغزش یه سرنخه، نه اثبات. حالا ببندش.'
        : 'واکنش عادی؛ سرنخی نیست. یه مدرک یا مظنون دیگه رو امتحان کن.';
    if (mounted) setState(() => _step = 3);
    return (text: text, left: _left);
  }

  Future<void> _openSuspect(Suspect s) async {
    if (_step < 2) {
      _hint('اول مرحله‌ی بالا رو انجام بده');
      return;
    }
    if (_step >= 4) return;
    final w = WeekendShow(
      caseId: 'practice',
      evidence: _case.evidence.take(2).toList(),
      shows: _shows,
      left: _left,
      localShow: _localShow,
      highlight: true,
      coach: Builder(builder: (ctx) => _SheetCoach(note: _sheetNote, left: _leftN, onSkip: () {
            Navigator.of(ctx).pop();
            _close();
          })),
    );
    final m = await showSuspect(context, s, _marks[s.id] ?? SuspectMark.none, onMark: (m) => _marks[s.id] = m, weekend: w);
    if (m != null) _marks[s.id] = m;
    if (!mounted) return;
    if (_slip && _step < 4) setState(() => _step = 4);
  }

  void _pickWho() {
    final id = _pickSuspect;
    if (id == null) return;
    if (id == _culprit) {
      setState(() {
        _accuseStage = 1;
        _accuseNote = null;
      });
    } else {
      setState(() {
        _badSuspects.add(id);
        _pickSuspect = null;
        _tries = _tries <= 1 ? 3 : _tries - 1; // practice: tries refill instead of ending the case
        _accuseNote = 'اشتباه بود. تو بازی واقعی یه فرصت از دستت می‌رفت. یکی دیگه رو امتحان کن.';
      });
    }
  }

  void _pickWhyDone() {
    final id = _pickWhy;
    if (id == null) return;
    if (id == _rightWhy) {
      setState(() {
        _phase = _Phase.done;
        _step = 5;
      });
    } else {
      setState(() {
        _badWhys.add(id);
        _pickWhy = null;
        _accuseNote = 'مقصر درسته ولی «چرا و چطور» نه؛ تو بازی واقعی ستاره‌ی کامل نمی‌گرفتی. دوباره امتحان کن.';
      });
    }
  }

  // ------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GrainBackground(
        child: SafeArea(
          child: Column(children: [
            _top(),
            Expanded(
              child: switch (_phase) {
                _Phase.board => _board(),
                _Phase.accuse => _accuse(),
                _Phase.done => _finale(),
              },
            ),
            _coach(),
          ]),
        ),
      ),
    );
  }

  Widget _top() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [
          const Icon(Icons.school_rounded, color: K.brass, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('تمرین پرونده‌ی آخر هفته', style: tDisplay(17), maxLines: 1, overflow: TextOverflow.ellipsis)),
          for (int i = 0; i < 6; i++)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsetsDirectional.only(start: 4),
              decoration: BoxDecoration(shape: BoxShape.circle, color: i <= _step ? K.brass : K.night3),
            ),
        ]),
      );

  Widget _coach() {
    final last = _step == 5 && _phase == _Phase.done;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: SingleChildScrollView(
        child: Paper(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('قدم ${fa(_step + 1)} از ${fa(6)}', style: tBody(12, color: K.inkSoft, w: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(_coachText, key: const ValueKey('coach_text'), style: tBody(15, color: K.ink, w: FontWeight.w700)),
            if (last) ...[
              const SizedBox(height: 10),
              StampButton(label: 'بزن بریم', icon: Icons.arrow_back_rounded, onTap: _close),
            ],
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: _close,
                child: Text('رد کردن', style: tBody(13, color: K.inkSoft, w: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _board() {
    final c = _case;
    final open = c.evidence.take(2).toList();
    final locked = c.evidence.skip(2).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 8), children: [
      Text(c.title, style: tDisplay(22)),
      Text(c.location, style: tBody(12, color: K.textSoft)),
      const SizedBox(height: 10),
      // chapters
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: _Glow(
            on: false,
            child: _chapterTile(icon: Icons.lock_open_rounded, title: 'فصل ۱', sub: 'باز است', color: K.ok),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            key: const ValueKey('tut_ch2'),
            onTap: _tapChapter2,
            child: _Glow(
              on: _step == 0,
              child: _chapterTile(icon: Icons.lock_rounded, title: 'فصل ۲', sub: 'باز می‌شه تا ${faClock(_countdown)}', color: K.textSoft),
            ),
          ),
        ),
      ]),
      ),
      const SizedBox(height: 12),
      Paper(child: Text(c.intro, style: tBody(15, color: K.ink))),
      const SizedBox(height: 12),
      Text('مدارک', style: tBody(14, w: FontWeight.w700)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in open) _evidenceCard(e, false),
        for (final e in locked) _evidenceCard(e, true),
      ]),
      const SizedBox(height: 12),
      Text('مظنون‌ها', style: tBody(14, w: FontWeight.w700)),
      const SizedBox(height: 6),
      _Glow(
        on: _step == 2 || (_step == 3 && !_slip),
        child: Wrap(key: const ValueKey('tut_suspects'), spacing: 8, runSpacing: 8, children: [
          for (final s in c.suspects) SuspectChip(suspect: s, onTap: () => _openSuspect(s)),
        ]),
      ),
      const SizedBox(height: 16),
      Row(children: [
        for (int i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 3),
            child: Icon(Icons.gavel_rounded, size: 16, color: i < _tries ? K.stamp : K.textSoft.withValues(alpha: 0.3)),
          ),
        const SizedBox(width: 6),
        Flexible(child: Text('${fa(_tries)} فرصت متهم کردن (تمرینی)', style: tBody(12, color: K.textSoft))),
      ]),
      const SizedBox(height: 8),
      _Glow(
        on: _step == 1 || (_step == 4 && _phase == _Phase.board),
        child: StampButton(key: const ValueKey('tut_accuse'), label: 'متهم کردن', icon: Icons.gavel_rounded, onTap: _tapAccuse),
      ),
    ]);
  }

  Widget _chapterTile({required IconData icon, required String title, required String sub, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.6))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Flexible(child: Text(title, style: tBody(15, w: FontWeight.w900), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 4),
        Text(sub, style: tBody(12.5, color: K.textSoft)),
      ]),
    );
  }

  Widget _evidenceCard(Evidence e, bool locked) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: locked ? K.night3 : K.paper,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: locked ? K.textSoft.withValues(alpha: 0.4) : K.kraft),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(locked ? Icons.lock_rounded : Icons.description_rounded, size: 16, color: locked ? K.textSoft : K.inkSoft),
          const SizedBox(width: 6),
          Expanded(child: Text(e.title, style: tBody(13, color: locked ? K.textSoft : K.ink, w: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 4),
        Text(locked ? 'فصل ۲' : e.text, style: tBody(11.5, color: locked ? K.textSoft : K.inkSoft), maxLines: 3, overflow: TextOverflow.ellipsis),
      ]),
    );
  }

  Widget _accuse() {
    final c = _case;
    final who = _accuseStage == 0;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 8), children: [
      Text(who ? 'چه کسی؟' : 'چرا و چطور؟', style: tDisplay(22)),
      const SizedBox(height: 8),
      if (_accuseNote != null) ...[
        Text(_accuseNote!, style: tBody(13.5, color: K.stamp, w: FontWeight.w700)),
        const SizedBox(height: 8),
      ],
      if (who)
        for (final s in c.suspects)
          _choice(
            key: ValueKey('who_${s.id}'),
            title: s.name,
            sub: s.role,
            selected: _pickSuspect == s.id,
            bad: _badSuspects.contains(s.id),
            leading: SuspectPortrait(s.avatar, size: 44, circle: true),
            onTap: () => setState(() => _pickSuspect = s.id),
          )
      else
        for (final m in c.motives)
          _choice(
            key: ValueKey('why_${m.id}'),
            title: m.text,
            selected: _pickWhy == m.id,
            bad: _badWhys.contains(m.id),
            onTap: () => setState(() => _pickWhy = m.id),
          ),
      const SizedBox(height: 10),
      StampButton(
        key: const ValueKey('tut_confirm'),
        label: who ? 'متهمش کن' : 'ثبتش کن',
        icon: Icons.gavel_rounded,
        onTap: (who ? _pickSuspect : _pickWhy) == null ? null : (who ? _pickWho : _pickWhyDone),
      ),
    ]);
  }

  Widget _choice({
    required Key key,
    required String title,
    String? sub,
    required bool selected,
    required bool bad,
    Widget? leading,
    required VoidCallback onTap,
  }) {
    final color = bad ? K.stamp : (selected ? K.brass : K.kraft.withValues(alpha: 0.4));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        key: key,
        onTap: bad ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? K.night3 : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color, width: selected || bad ? 2 : 1),
          ),
          child: Row(children: [
            if (leading != null) ...[leading, const SizedBox(width: 10)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: tBody(14.5, w: FontWeight.w700)),
                if (sub != null) Text(sub, style: tBody(12.5, color: K.textSoft)),
              ]),
            ),
            if (bad) Text('اشتباه', style: tBody(12, color: K.stamp, w: FontWeight.w900)),
          ]),
        ),
      ),
    );
  }

  Widget _finale() {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), children: [
      Center(child: Text('پرونده حل شد!', style: tDisplay(24))),
      const SizedBox(height: 10),
      const Center(child: Stars(count: 3, size: 40)),
      const SizedBox(height: 8),
      Center(
        child: Text('هر دو قدم درست بود: ۳ ستاره', textAlign: TextAlign.center, style: tBody(14, color: K.brass, w: FontWeight.w700)),
      ),
      const SizedBox(height: 12),
      Paper(
        child: Text(
          'اینجا فقط تمرین بود و سکه‌ای نگرفتی. تو پرونده‌ی واقعی اگه از فصل ۱ درست بگی، ${fa(Api.i.weeklyEarlyBonus)} سکه‌ی اضافه هم می‌گیری.',
          style: tBody(14, color: K.ink),
        ),
      ),
    ]);
  }
}

/// A glowing frame around the thing the player must tap (a static glow: nothing moves, so it is reduce-motion safe).
class _Glow extends StatelessWidget {
  const _Glow({required this.on, required this.child});
  final bool on;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: on ? K.brass : Colors.transparent, width: 2.5),
        boxShadow: on ? [BoxShadow(color: K.brass.withValues(alpha: 0.4), blurRadius: 14)] : null,
      ),
      child: child,
    );
  }
}

/// The coach card drawn at the top of the suspect sheet: what to do, the show counter and a skip button.
class _SheetCoach extends StatelessWidget {
  const _SheetCoach({required this.note, required this.left, required this.onSkip});
  final ValueNotifier<String> note;
  final ValueNotifier<int> left;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Paper(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: ListenableBuilder(
        listenable: Listenable.merge([note, left]),
        builder: (_, __) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.tips_and_updates_rounded, color: K.stamp, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text('نشان دادن مدرک', style: tBody(13, color: K.inkSoft, w: FontWeight.w900))),
            Container(
              key: const ValueKey('tut_counter'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: K.night, borderRadius: BorderRadius.circular(99)),
              child: Text('${fa(left.value)} از ${fa(3)}', style: tBody(12.5, color: K.brass, w: FontWeight.w900)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(note.value, key: const ValueKey('sheet_note'), style: tBody(14, color: K.ink, w: FontWeight.w700)),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(onPressed: onSkip, child: Text('رد کردن', style: tBody(13, color: K.inkSoft, w: FontWeight.w700))),
          ),
        ]),
      ),
    );
  }
}
