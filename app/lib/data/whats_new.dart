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
  WhatsNewRelease(69, '۱.۳۷', '2026-10-23', [
    WhatsNewItem('tools_v2', 'ابزارهای کارآگاهی پررنگ‌تر شدن و حالا توی پرونده‌های آخر هفته هم کار می‌کنن (هر شب یک بار از هر کدوم)', WhatsNewTarget.weekend),
    WhatsNewItem('tools_help', 'دکمه‌ی «چطور کار می‌کنن؟» بالای ابزارها می‌گه هر کدوم چطور به دست میاد، چقدره و کجا استفاده می‌شه؛ قبل از هر استفاده هم می‌بینی چی نشونت می‌ده', WhatsNewTarget.caseToday),
    WhatsNewItem('tools_fingerprint', 'اثر انگشت‌خوان دیگه نمی‌گه کسی «نقش داره»؛ فقط می‌گه اسمش توی چند مدرک اومده و حکم گناه نمی‌ده. اگه چیزی پیدا نشه، سکه‌ای کم نمی‌شه', WhatsNewTarget.caseToday),
    WhatsNewItem('tools_magnifier', 'ذره‌بین حالا روی همه‌ی پرونده‌ها کار می‌کنه و یکی از مدارک غیراصلی رو علامت می‌زنه تا وقتت تلف نشه', WhatsNewTarget.caseToday),
    WhatsNewItem('tools_camera', 'دوربین مخفی برای پرونده‌های تازه و آخر هفته مشاهده‌ی بی‌طرف درباره‌ی هر مظنون نشون می‌ده', WhatsNewTarget.weekend),
  ]),
  WhatsNewRelease(68, '۱.۳۶', '2026-10-22', [
    WhatsNewItem('nav_five_tabs', 'نوار پایین حالا پنج تب داره: خانه، بایگانی، آخر هفته، برترها و پروفایل؛ بایگانی یک ضربه بیشتر فاصله نداره', WhatsNewTarget.archive),
    WhatsNewItem('home_calm', 'صفحه‌ی خانه مرتب‌تر شد: پرونده‌ی امشب، بایگانی و آخر هفته کنار هم، مأموریت‌ها و زنجیره فشرده، و بقیه (داستان، دعوت، فروشگاه) توی «تازه‌ها»', WhatsNewTarget.caseToday),
    WhatsNewItem('rating_calm', 'امتیاز دادن به پرونده‌های بایگانی دیگه زود «کمی صبر کن» نمی‌ده؛ می‌تونی پشت سر هم به چندتا پرونده ستاره بدی', WhatsNewTarget.archive),
    WhatsNewItem('share_card', 'کارت اشتراک نتیجه حالا کوتاهه (پلاک، مدرک و دقیقه) و هیچ‌چیزی از جواب پرونده لو نمی‌ده', WhatsNewTarget.caseToday),
    WhatsNewItem('fair_week', 'جدول هفته به پیوستگی جایزه می‌ده: اول شب‌های حل‌شده، بعد پلاک؛ هر شب هم بین حل‌کننده‌های ۳ پلاکیِ پرونده یک کارآگاه قرعه‌کشی می‌شه', WhatsNewTarget.leaderboard),
  ]),
  WhatsNewRelease(67, '۱.۳۵', '2026-10-21', [
    WhatsNewItem('board_calm', 'جدول برترها آروم‌تره: فقط یه خط توضیح می‌بینی و بقیه‌اش پشت دکمه‌ی «i» کنار عنوانه؛ لیگ‌ها هم همیشه روی صفحه‌ان', WhatsNewTarget.leaderboard),
    WhatsNewItem('board_leagues', 'لیگ هر کارآگاه و بازه‌ی رتبه‌هاش توی «i» نوشته شده؛ رتبه‌ی کنار اسم همیشه همون رتبه‌ی پروفایله', WhatsNewTarget.leaderboard),
    WhatsNewItem('weekend_chapters', 'توی پرونده‌های آخر هفته هر مدرک و مظنون نشان فصل خودش رو داره، موارد تازه «تازه» دارن و می‌تونی بر اساس فصل فیلتر کنی', WhatsNewTarget.weekend, tags: ['weekend_chapters']),
  ]),
  WhatsNewRelease(66, '۱.۳۳', '2026-10-20', [
    WhatsNewItem('tools_tray', 'ابزارهای کارآگاهی توی پرونده‌های روزانه: اثر انگشت‌خوان، ذره‌بین و دوربین مخفی (هر پرونده هر کدوم رو داشته باشه)؛ پلاکی کم نمی‌شه', WhatsNewTarget.caseToday),
    WhatsNewItem('tools_free', 'از هر ابزار اولیش رایگانه تا امتحانش کنی؛ بعدش با سکه می‌گیری یا گاهی از مأموریت‌ها و نشان‌ها هدیه می‌گیری', WhatsNewTarget.caseToday),
  ]),
  WhatsNewRelease(65, '۱.۳۲', '2026-10-20', [
    WhatsNewItem('streak_ladder', 'زنجیره حالا تا ۳۶۵ شب پله داره (۳، ۷، ۱۴، ۳۰، ۶۰، ۱۰۰، ۲۰۰، ۳۶۵) و کارت زنجیره می‌گه چند شب مونده', WhatsNewTarget.caseToday),
    WhatsNewItem('streak_frames', 'سه قاب آتشی تازه برای زنجیره‌های ۶۰، ۲۰۰ و ۳۶۵ شبه؛ همیشه مال خودته', WhatsNewTarget.avatars),
    WhatsNewItem('streak_flame', 'کنار اسم کارآگاه‌ها توی جدول برترها یه شعله با تعداد شب‌های پیاپی‌شون می‌بینی', WhatsNewTarget.leaderboard),
    WhatsNewItem('streak_repair', 'اگه زنجیره‌ات دیشب شکسته باشه، یک بار می‌تونی با سکه ترمیمش کنی', WhatsNewTarget.caseToday),
  ]),
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
