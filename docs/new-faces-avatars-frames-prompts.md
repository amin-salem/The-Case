# Image prompts: new suspect faces, profile avatars, frames (26 Oct 2026)

Why these exact numbers: the game has 304 suspects and only 80 faces. The shortage is almost all MEN (docs/portrait-ages.json has the apparent age of every face).

| group | suspects needing it | faces today | ask for |
|---|---|---|---|
| old men (55-75) | 51 | 4 (+4 that look 50-55) | **14** |
| mid men (36-52) | 113 | 11 | **10** |
| young men (20-32) | 37 | 7 | **6** |
| young women (22-32) | 25 | 9 | **8** |
| mid women (36-52) | 78 | 29 | **6** |
| old women | 4 | 16 | none, enough |

Generate in ONE chat per group, ask for "a different person every time", and look at the 4 previous results before accepting the next one: repetition comes from similar hair + clothes + angle, so the lists below change all three on purpose.

## 1. Suspect faces (square 1:1, at least 1024 px, keep the same look as the existing ones)

### Style block (paste at the start of every prompt)
```
Cinematic noir portrait photograph of an Iranian [PERSON], shoulders-up, 1:1 square, head slightly off-centre,
shot on 85mm f/1.8, dramatic low-key lighting: one warm amber-orange rim light from one side, deep navy-blue
background fading to black, subtle film grain, realistic skin texture with pores and fine lines, natural
unretouched look, serious detective-story mood, no text, no watermark, no logo, no extra people, no hands
covering the face, one single person only.
```
Rules to repeat in every prompt: **the person must look their stated age (wrinkles, hair colour, skin) and must NOT look like a model or like any previous image.** Women wear a headscarf or a scarf over the hair, as in the existing set; men have no covering unless the prompt says.

Save as `m_old_<word>.png` etc. (gender_age_job). Give me the files and I do the rest (WebP, registration, age table, spread over the cases).

### 1a. OLD MEN (14), apparent age 58-75
Replace [PERSON] in the style block with the line below.
1. `m_old_baker`: 68-year-old man, bald with white fringe, round face, flour-dusted dark apron, kind but tired eyes, white stubble.
2. `m_old_clerk`: 63-year-old man, thin, sharp cheekbones, grey slicked-back hair, rimless glasses, buttoned grey cardigan over a shirt, thin moustache.
3. `m_old_farmer`: 70-year-old man, sun-burnt weathered skin, deep wrinkles, white thick moustache, brown woollen flat cap, rough wool jacket, gentle squint.
4. `m_old_doctor`: 66-year-old man, full silver hair combed back, trimmed silver beard, half-moon reading glasses, dark suit with a small pin, stethoscope strap barely visible.
5. `m_old_cleric`: 72-year-old man, long white beard, white turban and brown cloak, calm heavy-lidded eyes, strong nose.
6. `m_old_watchman`: 64-year-old man, heavy build, double chin, grey crew-cut, thick grey moustache, dark security jacket with a faded badge, suspicious stare.
7. `m_old_tailor`: 67-year-old man, thin hair, big round tortoiseshell glasses, measuring tape around the neck, waistcoat, pins on the lapel.
8. `m_old_merchant`: 61-year-old man, dyed jet-black hair and moustache (obviously dyed), gold ring, expensive dark overcoat, confident half-smile.
9. `m_old_retired`: 69-year-old man, full white curly hair, clean shaven, deep laugh lines, mustard knitted vest, warm friendly face.
10. `m_old_driver`: 62-year-old man, short grey beard, flat newsboy cap, leather jacket, tired red-rimmed eyes, tough face.
11. `m_old_judge`: 71-year-old man, receding white hair, thick black-rimmed glasses, severe frown, dark formal coat and tie.
12. `m_old_fisherman`: 65-year-old man, tanned leathery face, grey stubble, wool beanie, heavy knitted sweater, scar on the chin.
13. `m_old_artist`: 66-year-old man, wild white hair, white goatee, paint stain on the cheek, scarf, loose dark shirt, dreamy eyes.
14. `m_old_porter`: 74-year-old man, very thin, deep-set eyes, white stubble, brown wool coat with a high collar, trembling worried expression.

### 1b. MID-AGE MEN (10), apparent age 38-50
1. `m_mid_pharmacist`: 40, clean shaven, neat side parting, wire glasses, white coat collar visible.
2. `m_mid_engineer`: 44, thick dark hair with grey temples, short beard, safety-yellow jacket collar, calm.
3. `m_mid_cook`: 47, stocky, shaved head, big black moustache, white kitchen jacket, sweaty forehead.
4. `m_mid_clerk`: 42, thin face, very short hair, tired eyes with dark circles, open grey shirt collar, no tie.
5. `m_mid_cop`: 45, strong jaw, dark short hair, dark blue uniform shirt with epaulettes, stern.
6. `m_mid_journalist`: 39, messy dark hair, three-day stubble, canvas jacket, camera strap on the shoulder.
7. `m_mid_teacher`: 48, balding, round glasses, tweed jacket, ink stain on the shirt pocket, gentle expression.
8. `m_mid_butler`: 50, receding grey hair, perfectly groomed thin moustache, dark waistcoat and bow tie, expressionless.
9. `m_mid_mechanic`: 43, oil smudge on the cheek, thick eyebrows, dark overalls, wiry build, grin.
10. `m_mid_banker`: 46, silver temples, trimmed salt-and-pepper beard, expensive navy suit, cold stare.

### 1c. YOUNG MEN (6), apparent age 22-31
1. `m_young_courier`: 24, curly dark hair, helmet strap, windbreaker hood down, quick eyes.
2. `m_young_barista`: 27, man-bun, full short beard, apron strap, friendly slightly nervous smile.
3. `m_young_soldier`: 22, buzz cut, olive military collar, very serious, young face.
4. `m_young_designer`: 29, undercut, round glasses, small silver earring, black turtleneck.
5. `m_young_boxer`: 26, broken nose, short curly hair, hooded sweatshirt, bruise under the eye.
6. `m_young_student2`: 21, thin, messy fringe, thin moustache just starting, backpack strap, anxious.

### 1d. YOUNG WOMEN (8), apparent age 22-31 (different from the existing nine)
1. `f_young_chef`: 28, strong eyebrows, dark scarf tied back like a bandana, chef jacket collar, flour on the cheek.
2. `f_young_pilot`: 30, sharp eyes, navy scarf, uniform collar with a small gold wing pin.
3. `f_young_lawyer`: 29, round glasses, burgundy scarf, blazer, composed, slight smile.
4. `f_young_photographer`: 26, freckles, loose curls escaping the scarf, camera strap, mustard scarf.
5. `f_young_cleaner`: 31, tired, scarf in dull green, rubber-glove cuff visible, plain work coat.
6. `f_young_courier`: 25, short hair under a scarf, reflective jacket collar, windblown, determined.
7. `f_young_pharmacist`: 27, soft round face, thin gold glasses, light grey scarf, white coat.
8. `f_young_singer`: 30, bold dark lipstick, patterned silk scarf, small earrings, dreamy.

### 1e. MID-AGE WOMEN (6), apparent age 38-50
1. `f_mid_judge`: 49, severe, grey streak, black scarf, dark robe collar.
2. `f_mid_accountant`: 44, small rectangular glasses, beige scarf, cardigan, worried.
3. `f_mid_vendor`: 41, strong laugh lines, colourful patterned scarf, woollen vest, warm.
4. `f_mid_surgeon`: 45, surgical cap tucked under a scarf, mask pulled below the chin, intense eyes.
5. `f_mid_captain`: 47, dark navy scarf, officer jacket with a single gold stripe, weathered tanned skin.
6. `f_mid_baker2`: 38, rosy cheeks, flour dust on the scarf, hazel eyes, apron strap.

## 2. New profile avatars (existing ones: stylised painterly illustration, shoulders-up, moonlit blue circle behind, 384 px)

### Style block
```
Stylised semi-realistic digital illustration portrait of [CHARACTER], shoulders-up, centred, thick clean painterly
linework, rich warm skin tones, deep navy-blue night background with a soft glowing moon-blue circle behind the
head, subtle rim light, game avatar icon, 1:1 square, no text, no watermark.
```
Characters (Persian title in brackets = the name in the shop):
1. «ماهیگیر سپیده‌دم»: weathered fisherman detective with a yellow raincoat and a lantern, harbour fog behind. (rare, goal: 100 cases)
2. «کتابدار رازها»: elegant woman in a long scarf and round glasses, an open old book glowing in her hands, tall shelves. (epic, shop)
3. «بازرس زیر باران»: hooded inspector in a wet trench coat, rain streaks and a glowing street lamp, face half in shadow. (epic, shop)
4. «جنایی‌نویس»: bearded writer with a typewriter ribbon around his neck and a cigarette pipe (no smoke), crumpled pages floating. (epic, shop)
5. «کارآگاه فضایی نوآر»: retro-futuristic detective with a transparent visor and a tiny drone, neon city window. (legendary, shop)
6. «پزشک قانونی»: calm woman in a white coat and a scarf, a magnifying glass over a fingerprint card, cold teal light. (epic, goal: 25 three-star cases)
7. «راننده‌ی تاکسی شب»: old taxi driver in a flat cap, a yellow taxi light glowing behind, a thermos in hand. (rare, shop)
8. «دختر ساعت‌ساز»: young woman with a loupe on her forehead and tiny gears floating around, brass colours. (epic, goal: 200 nights streak)
9. «گرگ‌ و میش»: two-face portrait, half in light half in shadow, detective half-mask, mysterious. (legendary, goal: top 3 of a week five times)
10. «نگهبان کتابخانه‌ی قدیمی»: serious guard with a huge key ring and a lantern, stone arches behind. (rare, shop)

## 3. New frames (circular ring around the avatar)
The current frames are drawn in code, so the code can make new ones too (I will do those). If you prefer painted frames, ask for each as a **transparent PNG, 512x512, circular ring only, empty centre, nothing outside the ring**:
```
A circular ornamental avatar frame, perfectly round, 512x512, transparent background, empty transparent centre
(a circle of 70% of the width left clear), [DESCRIPTION], centred, symmetrical, high detail, clean edge, no text,
no avatar inside, no shadow outside the ring.
```
1. «زنجیر آهنین»: thick forged iron chain links with a tiny padlock at the bottom, dark steel with warm highlights.
2. «ماه نیمه‌شب»: silver ring with a crescent moon and tiny stars, glowing blue edge.
3. «طومار قدیمی»: parchment scroll curled into a ring with wax seal, ink swirls, warm brown.
4. «کنده‌کاری قاجاری»: gold floral arabesque ring (Persian tile motifs) with turquoise stones.
5. «نور پلیس»: ring of alternating red and blue light glow, tiny siren lights on top.
6. «نقاب نوآر»: black ring with white piano-key pattern and a thin gold line.
7. «تاج پرونده‌ها»: gold laurel crown ring with a small magnifier emblem on top.
8. «یخ و شیشه»: frosted glass ring with ice crystals and cold cyan glow (for winter events).

## 4. Check list before sending me images
- Every face looks the stated age; no two of the batch share hair + clothing + angle.
- No hands over the face, no text, no logos, one person only.
- Square, at least 1024 px (I shrink them to 512).
