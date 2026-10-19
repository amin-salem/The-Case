import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';

class _Page {
  const _Page(this.icon, this.title, this.body, [this.points = const []]);
  final IconData icon;
  final String title;
  final String body;
  final List<String> points;
}

const _pages = <_Page>[
  _Page(Icons.folder_special_rounded, 'به «پرونده» خوش اومدی',
      'تو یه کارآگاهی. هر شب یه پرونده‌ی جنایی جدید باز می‌شه و باید قاتل رو پیدا کنی؛ نه با حدس، با دلیل.',
      ['هر پرونده فقط یه جواب درست داره', 'جواب رو باید بشه ثابت کرد، نه حدس زد']),
  _Page(Icons.nightlight_round, 'پرونده‌ی هر شب',
      'هر شب ساعت ۲۱:۰۰ یه پرونده‌ی تازه باز می‌شه. هر وقت خواستی سراغش برو؛ پرونده‌های قبلی هم توی بایگانی می‌مونن.',
      ['اگه حلش کنی، رکورد روزهای پشت‌سرهمت بالا می‌ره', 'ماموریت‌های امروز توی صفحه‌ی اصلی هستن']),
  _Page(Icons.search_rounded, 'بررسی پرونده',
      'پرونده سه بخش داره: ماجرا، مدارک و مظنون‌ها. مدارک رو بخون، با مظنون‌ها صحبت کن و ببین حرف‌هاشون با مدارک جور درمیاد یا نه.',
      [
        'روی هر مظنون بزن و ازش سؤال بپرس',
        'با «مشکوک» یا «بی‌گناه» علامتش بزن؛ علامت‌ها ذخیره می‌شن',
        'مدرک مهم رو سنجاق کن تا بعداً پیداش کنی',
        'دروغ‌ها معمولاً با ترکیب چند مدرک لو می‌رن'
      ]),
  _Page(Icons.gavel_rounded, 'متهم کردن و پلاک',
      'وقتی مطمئن شدی، قاتل و انگیزه‌ی اصلی رو انتخاب کن. هر پرونده تعداد محدودی فرصت داره.',
      [
        'هرچی کمتر کمک بگیری و زودتر درست جواب بدی، پلاک بیشتر',
        'برای ۳ پلاک، پرونده رو کامل بررسی کن',
        'کمک (راهنما) با سکه گرفته می‌شه',
        'اگه نتونستی، جواب بعد از بسته شدن پرونده منتشر می‌شه'
      ]),
  _Page(Icons.weekend_rounded, 'پرونده‌ی آخر هفته',
      'هر هفته یه پرونده‌ی بزرگ‌تر و دوشبه هست. پنجشنبه صبح ساعت ۹ شب اولش باز می‌شه، شب دوم همون روز ساعت ۲۱ یه مظنون تازه و مدارک جدید می‌آره و تا جمعه ساعت ۲۱ وقت داری.',
      ['از همون شب اول می‌تونی متهم کنی؛ کامل حل کنی قبل از شب دوم، سکه‌ی اضافه و پلاک می‌گیری', 'شب اول یه سؤال کوچیک هم هست: «کی دروغ می‌گه؟»', 'تا جمعه ساعت ۲۱ وقت داری']),
  _Page(Icons.menu_book_rounded, 'حالت داستان',
      'یه فصل داستانی با چند قسمت: تو همکار سرگرد ناصری هستی و با هر قسمت، یه پرونده‌ی مستقل و یه تکه از معمای بزرگ‌تر رو حل می‌کنی.',
      ['قسمت‌ها به‌ترتیب باز می‌شن', 'هر قسمت جداگانه قابل حله']),
  _Page(Icons.emoji_events_rounded, 'سکه، رتبه و جایزه',
      'با حل کردن پرونده‌ها سکه و امتیاز می‌گیری. سکه‌ها رو برای کمک و آواتار و قاب‌های ویژه خرج کن.',
      [
        'جدول رتبه‌ی هفتگی داری و ۱۰ کارآگاه اول جایزه می‌گیرن',
        'جایزه توی صندوق پیام‌ها میاد',
        'دستاوردها آواتار و قاب‌های مخصوص باز می‌کنن',
        'برای نگه داشتن پیشرفتت حساب رو با ایمیل امن کن'
      ]),
  _Page(Icons.notifications_active_rounded, 'هیچ پرونده‌ای رو از دست نده',
      'یادآورها رو روشن بذار تا موقع باز شدن پرونده‌ی شب، آخر هفته و داستان خبرت کنیم. هر وقت خواستی از تنظیمات خاموششون کن.',
      ['راهنمای کامل همیشه توی تنظیمات هست']),
];

/// First-run intro and the always-available full guide (Settings → راهنما).
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key, this.firstRun = false});
  final bool firstRun;

  /// Shows the intro once; returns when the player finishes or skips.
  static Future<void> maybeShowFirstRun(BuildContext context) async {
    if (Api.i.flag('intro_done')) return;
    await Api.i.setFlag('intro_done');
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GuideScreen(firstRun: true)));
  }

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  final _ctl = PageController();
  int _i = 0;

  void _next() {
    if (_i == _pages.length - 1) {
      Navigator.of(context).pop();
    } else {
      _ctl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _i == _pages.length - 1;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: K.night,
        body: SafeArea(
          child: Column(children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(widget.firstRun ? 'رد کردن' : 'بستن', style: const TextStyle(color: K.textSoft)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _ctl,
                itemCount: _pages.length,
                onPageChanged: (v) => setState(() => _i = v),
                itemBuilder: (_, n) {
                  final p = _pages[n];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    child: Column(children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: K.night3,
                            border: Border.all(color: K.brass.withValues(alpha: 0.6), width: 2)),
                        child: Icon(p.icon, size: 46, color: K.brass),
                      ),
                      const SizedBox(height: 22),
                      Text(p.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: K.text, fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      Text(p.body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: K.text, fontSize: 15.5, height: 1.8)),
                      const SizedBox(height: 18),
                      for (final s in p.points)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Padding(
                                padding: EdgeInsets.only(top: 4, left: 8),
                                child: Icon(Icons.check_circle_rounded, size: 16, color: K.ok)),
                            Expanded(
                                child: Text(s,
                                    style: const TextStyle(color: K.textSoft, fontSize: 14, height: 1.6))),
                          ]),
                        ),
                    ]),
                  );
                },
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var n = 0; n < _pages.length; n++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.all(3),
                  width: n == _i ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                      color: n == _i ? K.brass : K.night3, borderRadius: BorderRadius.circular(4)),
                ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: K.brass, foregroundColor: K.ink),
                  onPressed: _next,
                  child: Text(last ? (widget.firstRun ? 'شروع پرونده‌ها' : 'تمام') : 'بعدی',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
