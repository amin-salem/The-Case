/// Scene art for story chapters, matched by chapter id and scene id (the server content stays pure text).
/// A chapter without an entry plays exactly as before: no picture.
const _base = 'assets/story/s01ch02';

class StoryArt {
  const StoryArt(this.asset, {this.focusY = 0.0, required this.caption});
  final String asset;

  /// Where a wide banner crop of the tall picture looks: -1 top, 0 middle, 1 bottom.
  final double focusY;

  /// What the picture shows (screen readers and the fallback when the file is missing).
  final String caption;
}

const Map<String, Map<String, StoryArt>> _scenes = {
  's01ch02': {
    'sc1': StoryArt('$_base/reception.webp', focusY: -0.15, caption: 'پذیرش هتل ساحل'),
    'room': StoryArt('$_base/room.webp', focusY: -0.35, caption: 'اتاق ۳۱۱'),
    'corridor': StoryArt('$_base/corridor.webp', focusY: -0.2, caption: 'راهروی طبقه‌ی سوم'),
    'desk': StoryArt('$_base/reception.webp', focusY: 0.35, caption: 'پشت پیشخوان پذیرش'),
    'staff': StoryArt('$_base/reception.webp', focusY: -0.15, caption: 'پذیرش هتل ساحل'),
  },
};

/// The picture of a scene, or null.
StoryArt? storySceneArt(String chapterId, String sceneId) => _scenes[chapterId]?[sceneId];

/// The Taban opening photo: whole, and with the hole burnt over the fourth man.
const String kTabanPhotoIntact = '$_base/photo_intact.webp';
const String kTabanPhotoBurnt = '$_base/photo_burnt.webp';

/// Board clues that are the Taban photo: in chapter 2 the evidence card «جای خالی قاب عکس» (e6, what the player really
/// holds after the photo scene) and the extra board clue «قاب عکس تابان».
bool storyClueIsTabanPhoto(int chapter, String clueId) => chapter == 2 && (clueId == 'e6' || clueId == 'photo_detail');

/// Every asset this file points at (a test checks that they all exist).
List<String> storyArtAssets() => {
      for (final c in _scenes.values) for (final a in c.values) a.asset,
      kTabanPhotoIntact,
      kTabanPhotoBurnt,
    }.toList();
