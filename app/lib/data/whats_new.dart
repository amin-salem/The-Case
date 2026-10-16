/// «چی تازه شده؟»: the list of changes shown after an update. This file is DATA: to announce a release, add one
/// [WhatsNewRelease] at the TOP of [kWhatsNew] (see docs/operations.md, "What's new").
library;

/// Where a «برو به …» jump takes the player.
enum WhatsNewTarget { weekend, avatars, comments, caseToday, missions, archive }

extension WhatsNewTargetLabel on WhatsNewTarget {
  String get label => switch (this) {
        WhatsNewTarget.weekend => 'آخر هفته',
        WhatsNewTarget.avatars => 'پروفایل',
        WhatsNewTarget.comments => 'نظرها',
        WhatsNewTarget.caseToday => 'پرونده',
        WhatsNewTarget.missions => 'مأموریت‌ها',
        WhatsNewTarget.archive => 'بایگانی',
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
  WhatsNewRelease(55, '۱.۲۶', '2026-10-16', [
    WhatsNewItem('plaques', 'حل پرونده حالا «پلاک کارآگاهی» می‌گیره؛ ۳ پلاک یعنی بدون اشتباه', WhatsNewTarget.archive),
    WhatsNewItem('rate_hearts', 'امتیاز دادن به پرونده جدا شد: با قلب نظرت رو بده', WhatsNewTarget.comments),
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
