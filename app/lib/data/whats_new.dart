/// «چی تازه شده؟»: the list of changes shown after an update. This file is DATA: to announce a release, add one
/// [WhatsNewRelease] at the TOP of [kWhatsNew] (see docs/operations.md, "What's new").
library;

/// Where a «برو به …» jump takes the player.
enum WhatsNewTarget { weekend, avatars, comments, caseToday, missions, archive, leaderboard }

extension WhatsNewTargetLabel on WhatsNewTarget {
  String get label => switch (this) {
        WhatsNewTarget.weekend => 'آخر هفته',
        WhatsNewTarget.avatars => 'پروفایل',
        WhatsNewTarget.comments => 'نظرها',
        WhatsNewTarget.caseToday => 'پرونده',
        WhatsNewTarget.missions => 'مأموریت‌ها',
        WhatsNewTarget.archive => 'بایگانی',
        WhatsNewTarget.leaderboard => 'جدول برترها',
      };
}

class WhatsNewItem {
  const WhatsNewItem(this.id, this.title, this.target, {this.tags = const []});

  /// Unique and stable (never reused for another change).
  final String id;

  /// Title only, in the players' voice («کارآگاه», never «نفر»).
  final String title;
  final WhatsNewTarget target;

  /// Ids of the red «تازه» tags this change puts on screen (see WhatsNew.tagVisible).
  final List<String> tags;
}

class WhatsNewRelease {
  const WhatsNewRelease(this.id, this.version, this.date, this.items);

  /// The app build number (pubspec `+N`); a bigger id is a newer release.
  final int id;
  final String version;
  final String date; // yyyy-mm-dd
  final List<WhatsNewItem> items;
}

/// Newest first.
const List<WhatsNewRelease> kWhatsNew = [
  WhatsNewRelease(63, '۱.۳۱', '2026-10-20', [
    WhatsNewItem('lost_reopen', 'پرونده‌ای که باختی بسته می‌شه؛ با سکه (دو برابر قیمت عادی) می‌تونی یه فرصت دوباره بگیری', WhatsNewTarget.archive),
    WhatsNewItem('difficulty_prices', 'قیمت بایگانی و پاداش حل حالا به سختی پرونده بستگی داره: هرچی سخت‌تر، قیمت و پاداش بیشتر', WhatsNewTarget.archive),
  ]),
  WhatsNewRelease(62, '۱.۳۱', '2026-10-19', [
    WhatsNewItem('archive_popular', '«محبوب‌ترین» درست شد: پرونده‌هایی که کارآگاه‌های بیشتری بهشون امتیاز خوب دادن اول میان، بدون امتیازها آخر', WhatsNewTarget.archive),
    WhatsNewItem('archive_search', 'توی بایگانی می‌تونی جست‌وجو کنی و روی هر فیلتر تعداد پرونده‌ها رو ببینی', WhatsNewTarget.archive),
  ]),
  WhatsNewRelease(61, '۱.۳۰', '2026-10-18', [
    WhatsNewItem('bazaar_fix', 'خرید از کافه‌بازار درست شد: اتصال خودکار دوباره امتحان می‌شه و اگه مشکلی باشه دلیلش رو می‌گه', WhatsNewTarget.caseToday),
    WhatsNewItem('categories', 'هر پرونده یه موضوع داره (پزشکی، هنر، خانواده...) و توی بایگانی می‌تونی با موضوع فیلتر کنی', WhatsNewTarget.archive),
    WhatsNewItem('weekend_nights', 'پرونده‌ی آخر هفته دو شبه شد: شب اول «کی دروغ می‌گه؟»، شب دوم مظنون تازه. ساعتش: پنجشنبه ۹ صبح تا جمعه ۲۱', WhatsNewTarget.weekend),
  ]),
  WhatsNewRelease(58, '۱.۲۹', '2026-10-17', [
    WhatsNewItem('difficulty_bar', 'سختی پرونده حالا نوار رنگی ۵ سطحی با برچسب: از آسان (سبز) تا خیلی سخت (قرمز)', WhatsNewTarget.archive),
    WhatsNewItem('stars_back', 'امتیاز دوباره ستاره است: ۱ سمت راست، ۵ سمت چپ، با عدد زیر هر ستاره', WhatsNewTarget.comments),
  ]),
  WhatsNewRelease(57, '۱.۲۸', '2026-10-17', [
    WhatsNewItem('rate_sheet', 'بعد از حل پرونده، امتیازدادن با یه ضربه، توی یه پنجره‌ی کوچیک', WhatsNewTarget.comments),
    WhatsNewItem('rate_old', 'پرونده‌های قبلی که امتیاز ندادی توی بایگانی منتظرتن', WhatsNewTarget.archive),
    WhatsNewItem('warrant_rare', 'حکم بازرسی کم‌یاب‌تر شد؛ بقیه‌ش رو می‌تونی با سکه رد کنی', WhatsNewTarget.caseToday),
    WhatsNewItem('weekend_time', 'ساعت دقیق پرونده‌ی آخر هفته', WhatsNewTarget.weekend),
  ]),
  WhatsNewRelease(56, '۱.۲۷', '2026-10-17', [
    WhatsNewItem('fair_week', 'جدول هفتگی عادلانه شد: فقط پرونده‌های همین هفته حساب می‌شن و بایگانی توش نیست', WhatsNewTarget.leaderboard),
    WhatsNewItem('leagues', 'لیگ‌های هفتگی: کارآگاه‌های هم‌سطح با هم رقابت می‌کنن و ۳ کارآگاه اول هر لیگ جایزه می‌گیرن', WhatsNewTarget.leaderboard),
    WhatsNewItem('week_clock', 'هفته جمعه ساعت ۲۱ شروع می‌شه، همون لحظه‌ای که پرونده‌ی اول هفته باز می‌شه', WhatsNewTarget.leaderboard),
  ]),
  WhatsNewRelease(55, '۱.۲۶', '2026-10-16', [
    WhatsNewItem('plaques', 'حل پرونده حالا «پلاک کارآگاهی» می‌گیره؛ ۳ پلاک یعنی بدون اشتباه', WhatsNewTarget.archive),
    WhatsNewItem('rate_numbers', 'امتیاز پرونده با ستاره و عدد زیر هر ستاره: ۱ سمت راست، ۵ سمت چپ', WhatsNewTarget.comments),
  ]),
  WhatsNewRelease(54, '۱.۲۶', '2026-10-15', [
    WhatsNewItem('archive_v2', 'بایگانی تازه: امتیاز، قیمت و مرتب‌سازی', WhatsNewTarget.archive),
    WhatsNewItem('rate_step', 'بعد از هر پرونده، با یه ضربه ستاره بده', WhatsNewTarget.comments),
    WhatsNewItem('invite_step', 'کد دعوت دوستت رو موقع شروع بزن و سکه بگیر', WhatsNewTarget.avatars),
  ]),
  WhatsNewRelease(53, '۱.۲۵', '2026-10-14', [
    WhatsNewItem('weekend_v2', 'پرونده‌ی آخر هفته، قالب تازه', WhatsNewTarget.weekend, tags: ['weekend_tab', 'show_evidence']),
    WhatsNewItem('avatars_frames', 'آواتار و قاب‌های تازه', WhatsNewTarget.avatars),
    WhatsNewItem('stars_only', 'فقط ستاره بده؛ نظر نوشتن اختیاریه', WhatsNewTarget.comments),
    WhatsNewItem('wrong_red', 'اشتباه‌هات قرمز می‌شه و بعد از حل مرورشون می‌کنی', WhatsNewTarget.caseToday),
    WhatsNewItem('missions_21', 'مأموریت‌ها ساعت ۲۱ عوض می‌شن', WhatsNewTarget.missions),
  ]),
];
