# Voice of the app (user-facing texts in `app/lib`)

Applies to screens, widgets, toasts, dialogs and error texts. Does NOT apply to case content or story text (those follow
`docs/case-writing-rules.md`) or to store texts (see CLAUDE.md, «Store texts»).

## Four rules

1. **«تو», colloquial and polite.** «بزن»، «می‌تونی»، «می‌شه»، «رو» — never «شما»، «می‌توانید»، «می‌شود»، «را» in a button or
   toast. No harsh commands; the friendly verb is enough, a «لطفاً» is not needed.
2. **«‌ی» with a zero-width non-joiner, never «ـهٔ».** «پرونده‌ی»، «جایزه‌ی»، «فرضیه‌ی»، «همه‌ی» — not «پروندهٔ»، «جایزهٔ».
3. **Every error says what happened, what to do next, and that coins and progress are safe** when that is true
   («سکه و پیشرفتت سر جاشه، دوباره امتحان کن»). Never a bare code, never blame the player.
4. **Value in game terms, not percentages.** «≈ ۸ پرونده»، «ماهی ۱۲ پرونده یا بیشتر»، not «+۲۳٪ بیشتر». Every number
   shown comes from real data (price, coins, counts); when it is unknown the line is hidden. (Stats about other
   players, like «۶۰٪ حلش کردن», are facts, not value claims, and stay.)

## Glossary

- Player: «کارآگاه» (never «نفر»، «بازیکن»، «کاربر» in the UI). Suspects: «مظنون».
- «پرونده» = a case; «پرونده‌ی بایگانی» = an old case; «حکم بازرسی» = warrant; «سرنخ» = hint; «سکه» = coin.
- «کارآگاه ویژه» = the 30-day VIP card; «بسته‌ی شروع» = the one-time starter pack.
- «زنجیره» = the night streak; «بیمه‌ی زنجیره» = streak freeze.
- Colloquial forms: «تموم»، «می‌شه»، «نمی‌شه»، «سر جاشه»، and «‌ه / ‌ست» instead of a final «است» («تازه‌ست»).

## Lint

`app/test/app_voice_test.dart` scans `app/lib` (not `data/`, not comment lines) for a curated list of the worst offenders:
«ـهٔ» forms, «شما» as a word, «می‌شود»-type verbs, «بازیکن». Existing exceptions go into `allowed` in that test with a
reason. Add a pattern only when it has no false positives.
