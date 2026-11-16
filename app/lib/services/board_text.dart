import '../models/models.dart';
import '../theme.dart' show fa;

/// The texts of the boards that come from numbers (pure, so they are tested without a screen).

/// «۹:۴۲» for 582 seconds; hours only when there are some («۱:۰۵:۰۰»).
String boardTime(int seconds) {
  if (seconds < 0) seconds = 0;
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
  String two(int v) => fa(v).padLeft(2, '۰');
  return h > 0 ? '${fa(h)}:${two(m)}:${two(s)}' : '${fa(m)}:${two(s)}';
}

/// The line under my pinned row: how much passes the place above. Null when there is no gap (first place, or an old server).
String? gapLine(RankGap? gap) {
  if (gap == null || gap.diff <= 0 || gap.nextRank < 1) return null;
  final unit = switch (gap.unit) {
    'seconds' => 'ثانیه',
    'nights' => 'شب',
    _ => 'امتیاز',
  };
  return '${fa(gap.diff)} $unit تا رتبه‌ی بالاتر (رتبه‌ی ${fa(gap.nextRank)})';
}

/// Tonight's solver numbers as one short line; every part is dropped when its number is unknown. Null = nothing to say.
String? dailyStatsLine(DailyStats? d) {
  if (d == null || d.solved <= 0) return null;
  return [
    '${fa(d.solved)} کارآگاه حلش کردن',
    if (d.mean != null) 'میانگین ${boardTime(d.mean!)}' else if (d.median != null) 'میانه ${boardTime(d.median!)}',
  ].join(' · ');
}

/// The value at the end of a board row.
String boardValue(String period, int value) => switch (period) {
      'daily' => boardTime(value),
      'streak' => '${fa(value)} شب',
      _ => '${fa(value)} پلاک',
    };
