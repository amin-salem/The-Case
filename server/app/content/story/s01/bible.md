# Season 1 bible: «کبریت سوخته»

Written before chapter 1 so every chapter fits. Writers of later chapters: read this whole file, then
`docs/story-mode.md` and `docs/case-writing-rules.md`. Each chapter is a full, fair, self-contained case
(difficulty 5); the season mystery runs only through the **thread** (and small details in ناصری's lines).
Never let a chapter's solution depend on the season mystery.

City: **رازان** (fictional), with its covered bazaar, harbour, old industrial quarter. All people and
places are fictional. Nothing gory: the 1390 fire killed nobody; the watchman later died of a heart attack.

## The truth (revealed in chapter 10 only)

**Who:** **نرگس افشار** (41, born نرگس کاوه), the quiet records clerk of the رازان detective bureau's
archive and mail desk. Wears hijab, always polite, brings ناصری his files every morning. She is in the
player's world from the first minute (ch1 intro: «خانم افشار از بایگانی»), never as a suspect before ch10.

**Why:** In 1390 the **کبریت‌سازی تابان** match factory in the old industrial quarter burned down one
night. Its night watchman, **یدالله کاوه** (her father), was convicted of negligence (smoking on duty).
He died of a heart attack in prison in 1393, still saying he never smoked. The fire was really set by
four people for the insurance money and to sell the land: **فرهاد تابانی** (owner's son, the brain),
**جمشید رحیمی** (the factory accountant who moved stock and books out first), **سعید پرهام** (the fire
inspector who wrote "single origin, cigarette" although there were two origins), and the insurance
assessor **حسام وکیلی** who signed the claim in a week. The young officer who signed the police report
blaming the watchman was **ستوان ناصری**: his very first case, closed under pressure from his boss
**سرهنگ منوچهری**.

Three years ago نرگس, now working in the archive, read her father's file and saw that the evidence
pointing to a second origin had been "lost". She began stealing, one by one, the things that prove the
arson or were bought with its money, from the four men and the people around them.

**The burnt match:** every match is from the last box of تابان matches her father brought home the
week before the fire: thin wood, **green head**, a brand nobody has made since 1390. She burns each to
the end. It says: *this was paid for with the fire.* She leaves it for ناصری, the one man who should
recognise the brand. She never breaks anything (she opens locks cleanly; she learned from case files),
never strikes where someone is present, and keeps everything she takes, labelled, in a storage unit:
she wants none of it, she wants the 1390 file reopened.

**Why she gets caught in ch10:** the threads add up (brand → factory → night-staff list → only the
watchman's family had the last boxes → the archive check-out log of the 1390 file → her married name).
She does not run. In the final scene she hands ناصری the key of the storage unit: the stolen objects,
put together, prove the arson. ناصری reopens the case and testifies against his own 1390 report.

## ناصری's arc
- Ch1–3: sharp, sarcastic, obsessed ("he's playing with me"); tests the rookie, gives little credit.
  Seed in ch1 (lose outro): «روز اولم یه نگهبان شب رو گرفتم».
- Ch4: admits the تابان fire was his first case; gets defensive when the player asks.
- Ch5–6: starts trusting the player's eye; checks the old file himself, finds pages missing.
- Ch7: learns سرهنگ منوچهری knew the fire had two origins. Angry, quieter, less sarcastic.
- Ch8–9: realises the thief has always been one step ahead of the bureau: someone inside.
- Ch10: faces that it is the woman who brings him tea and files every morning. Chooses truth over his
  record: reopens 1390. Last line to the player: the rookie is now his partner, not his assistant.

## Chapters

Puzzle types follow `docs/case-writing-rules.md` §2: no type twice in a row, none more than twice.
Culprit slots vary. Not every culprit is the match thief: some are copycats, some committed a crime
the thief only touched.

| ch | title (working) | setting / scene | main type | culprit | the match thief's role |
|---|---|---|---|---|---|
| 1 | «هفت‌ستاره» | antique and gold shop, سرای آینه, the covered bazaar · `bazaar_night` | 3 not what it seemed | s4 | none: a **copycat** (the owner's son hides a necklace he pawned four months ago) |
| 2 | «اتاق ۳۱۱» | hotel by the harbour · `hotel` | 5 time trick | s2 | he stole an old photo from the room of جمشید رحیمی the same night; a hotel employee used the confusion to steal a ring |
| 3 | «نقشه‌ی گمشده» | city library, map room · `library` | 2 hidden relationship | s5 | none: a rare map stolen by two who pretend to be strangers; the thief separately took a notebook from retired inspector سعید پرهام, a library volunteer |
| 4 | «لنگرگاه سه» | harbour customs warehouse · `harbor` | 8 the witness is the liar | s1 | a real match theft (a cheque-book of the old insurance agent) frames a dockworker; the helpful foreman is the one who stole the cargo |
| 5 | «جعبه‌ی سبز» | night train to the south · `train` | 9 object biography | s3 | none directly: a box of green-head تابان matches passes through five hands; one of them stole a passenger's money |
| 6 | «پرده‌ی آخر» | theatre · `theater` | 4 wrong victim | s2 | a copycat uses the match to scare ناصری's old informant; the target was really someone else |
| 7 | «پرونده‌ی ۹۰» | insurance company office · `office` | 1 guilty knowledge | s4 | the thief took the original 1390 assessment; the chapter's culprit is a clerk who stole client money the same night |
| 8 | «ویلای تابانی» | فرهاد تابانی's villa on a rainy night · `villa_rain` | 7 two people, one plan | s5 | the police wait for the thief at the villa; a guest and the caretaker steal the safe's cash; the thief still gets in and out |
| 9 | «خرابه‌ی تابان» | ruins of the تابان factory · `warehouse` | 6 staged scene | s1 | someone stages a "match thief" death trap to end the chase (nobody hurt); the stager is فرهاد تابانی's man |
| 10 | «کبریت آخر» | the detective bureau and its archive · `office` | 10 motive inversion | s3 | **the match thief herself**: نرگس افشار. Everyone thinks greed or revenge; the real motive is to force the 1390 file open (nothing she took was sold; all of it is catalogued in her storage unit) |

### Threads (the `thread` field; each one shown after the chapter is finished)
1. An unstamped envelope reaches the bureau's **mail desk** the same afternoon, addressed to «همکار تازه‌ی
   سرگرد ناصری», with a green-head match: «اون یکی کار من نبود. خوش اومدی.» The rookie's name was in no
   file yet. *(inside knowledge; the brand's look)*
2. The photo he took from جمشید رحیمی: the **opening of کبریت‌سازی تابان, 1385**; four men in front of
   the gate. ناصری does not recognise them yet. *(the brand has a name: تابان)*
3. The notebook of retired fire inspector پرهام, page for 1390 torn out; the facing page still shows
   the pen pressure of the words «دو نقطه‌ی شروع». *(the fire had two origins)*
4. ناصری admits the تابان fire was his first case; he arrested the night watchman. *(ناصری's past)*
5. The match box's batch stamp: «۱۳۹۰/۰۸»: the last batch, made the week before the fire, never sold;
   workers took boxes home. *(the thief is tied to a factory worker's family)*
6. In the informant's papers: the 1390 night-staff list. Watchman: یدالله کاوه, «دختر: نرگس، ۲۵ ساله».
   *(a name, but not the married one)*
7. The stolen 1390 assessment was signed in a week; a note in سرهنگ منوچهری's hand: «یک نقطه بنویسید.»
   *(cover-up)*
8. The raid time was known only inside the bureau, yet the thief came an hour early. *(insider)*
9. The archive check-out log: the 1390 file has been taken out every month for three years; the
   borrower's line is always signed by the archive desk itself. *(the archive)*
10. Solved: نرگس افشار, born کاوه. ناصری reopens the 1390 file.

### Recurring people
- **نرگس افشار**: archive and mail desk; appears in ناصری's lines in ch1, 3, 6, 9 (bringing files,
  tea, the envelope). Never a suspect before ch10; she is never present at a scene.
- **فرهاد تابانی, جمشید رحیمی, سعید پرهام, حسام وکیلی**: victims of real match thefts in ch2, 3, 4, 8;
  never the chapter's culprit except فرهاد's man in ch9.
- **سرهنگ منوچهری** (retired): mentioned from ch4, appears in ch7.

## Chapter 1 summary (written)
Copycat. جلال نیک‌پی's son کامران pawned the «هفت‌ستاره» necklace in خرداد, while his father was in
hospital, and put a brass replica (made by the silversmith ملکی) in the safe. When the father sold the
necklace and the buyer's expert was due at 10:00, کامران came back at night with his own gate key,
took the replica, pried the back window **from inside** and left a common burnt match, copying the
newspapers. The real thief never breaks anything and uses green-head matches (ناصری's notes, e2).
