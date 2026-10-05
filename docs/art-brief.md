# «پرونده»: art brief and answers (5 Oct 2026)

## Part 1. Answers to your questions

### Weekly big case (A)
- Approved, not started. It waits until you say go.
- It will be **much harder** than the nightly cases:
  - 8 suspects and about 15 evidence cards
  - several false trails that each look like the full answer
  - a solution that needs **three or four clues combined**
  - it opens in three chapters (Thursday night, Friday morning, Friday night), and the last chapter brings a twist
- To solve it, the player names both **who** did it and **why** (out of three motives).

### Case timer
- **Today it is not fair.** The time counts from the first moment a case is opened until it is solved. A case opened, closed, and solved 3 days later shows 3 days.
- **The fix:**
  - Time counts **only while the case screen is open**. It pauses when the player goes home, switches tabs, locks the phone or closes the app, and continues when they return.
  - The server adds up the open periods. Each period is capped (for example 30 minutes), so leaving the phone open all night can't break it.
  - The daily leaderboard then shows real solving time.
- Small job; it can go in the next run.

### Pictures and animation
- My tools here **cannot generate images**. Today all scenes and characters are drawn in code, which is why they look simple.
- The plan:
  1. You make the images with an image tool (Midjourney, Leonardo, Ideogram, etc.) using the prompts below.
  2. You send me the files.
  3. I put them into the app with subtle movement (slow zoom, rain or fog layers, light flicker) and keep the code-drawn art as a fallback.

---

## Part 2. Art brief

### 2.1 Rules for every image
- **One style for everything.** Always use the style block below, and keep the same tool, model and settings for the whole set, so the images look like one game.
- **Fictional only.** No real people, no famous buildings, no logos or brand names.
- **No writing** anywhere in the image: no text, letters, signs or numbers.
- **No symbols:** no religious or political symbols, no flags.
- **Women wear hijab:** a headscarf (roosari), or a maghnaeh for nurses and officers. Modest clothing for everyone.
- **Setting:** contemporary Iran, but generic and fictional.

#### Style block
Paste this at the start of every prompt:

> moody noir illustration, painterly digital art, cinematic lighting, deep navy and charcoal shadows, warm amber and brass highlights, subtle film grain, muted desaturated colors with a single warm light source, mysterious atmosphere, contemporary Iran setting, highly detailed, no text, no letters, no logos

#### Words to avoid
If your tool has a negative prompt, use this:

> text, letters, watermark, signature, logo, flag, religious symbol, gore, blood, weapon pointed at viewer, bright saturated colors, cartoon, anime, 3d render, photo

#### Midjourney settings
Add these if you use Midjourney:
- **Scenes:** `--ar 16:9 --style raw --v 6.1 --s 150`
- **Portraits:** `--ar 1:1 --style raw --v 6.1 --s 150`
- **Same face, several images:** use `--cref` (character reference) when you need one character in more than one picture.

### 2.2 File specs
| Asset | Count | Size | Format | Background | Name |
|---|---|---|---|---|---|
| Scene backgrounds | 20 | **1920×1080** (16:9) | PNG or JPG | full scene | `scene_<id>.png` |
| Character portraits | 40 | **1024×1024** (1:1) | PNG | plain dark navy (#10141C) or transparent | `char_<code>.png` |
| Detective avatars (the player) | 12 | **1024×1024** | PNG | plain dark navy | `det_01.png` … `det_12.png` |
| Evidence-type icons | 6 | **512×512** | PNG, transparent | transparent | `ev_<type>.png` |

- **Scene safe area:** keep the important part (the main object or the light) in the **middle 60%** of the width. The app crops the sides on phones.
- **Portraits:** head and shoulders, the face centered, looking slightly toward the viewer. Leave a little space above the head.
- **File size:** anything up to 5 MB per file is fine. I compress everything to WebP; the whole pack ends up around 8–10 MB inside the app.
- **Delivery:** put everything in one zip, named exactly as in the table, and attach it to this chat.

### 2.3 Scene backgrounds (20)
Each prompt is: **style block + the text below**. All scenes are empty: no people, only atmosphere.

| id | Persian | Prompt |
|---|---|---|
| `bazaar_night` | بازار شب | a covered traditional bazaar corridor at night, brick vaulted ceiling, closed wooden shop shutters, one lantern glowing, wet stone floor reflecting amber light, empty and silent |
| `office` | دفتر کار | a dim executive office at night, heavy wooden desk with a green desk lamp, open safe in the corner, city lights through rainy window blinds |
| `train` | قطار | interior corridor of an old overnight sleeper train, compartment doors, warm wall lamps, dark landscape rushing past the windows |
| `museum` | موزه | a quiet museum hall at night, empty glass display case lit from inside, marble floor, long shadows, security light |
| `villa_rain` | ویلا زیر باران | a lonely northern villa among dark trees in heavy rain at night, one lit window, muddy path, lightning in the distance |
| `warehouse` | انبار | a large industrial warehouse at night, stacked crates and pallets, a single hanging lamp, dust in the light beam |
| `harbor` | بندر | a southern port at night, cargo containers, a moored fishing boat, fog over dark water, one dock light |
| `hospital` | بیمارستان | an empty hospital corridor at night, flickering fluorescent light, a medicine cart, an intensive care door half open |
| `library` | کتابخانه | an old manuscript library, tall wooden shelves, a reading desk with a green lamp, an open antique book with gold illumination, dust in the air |
| `theater` | تئاتر | an empty theater stage behind the curtain, hanging spotlights and ropes, red velvet curtain, a single spotlight on the stage floor |
| `hotel` | هتل | a hotel corridor at night, patterned carpet, numbered doors without visible numbers, soft wall lights, a room service tray on the floor |
| `kitchen` | آشپزخانه | a restaurant kitchen after hours, steel counters, copper pots, a walk-in cold room door, steam and warm light |
| `snow_lodge` | کلبه‌ی برفی | a mountain lodge in deep snow at night, footprints leading to the door, warm light from the windows, pine trees |
| `desert` | کویر | a desert caravanserai at dusk, mud-brick walls, camels resting in the distance, long shadows, first stars appearing |
| `subway` | مترو | an empty metro platform late at night, tiled walls, a train arriving with headlights in the tunnel, cold blue and warm amber light |
| `lab` | آزمایشگاه | a research laboratory at night, glass flasks, a freezer with a frosted door, microscope under a single lamp |
| `wedding` | عروسی | a wedding hall after the party, round tables with flowers, a gift table, fairy lights, chairs pushed back, empty |
| `school` | مدرسه | an empty classroom at dusk, wooden desks, a blackboard wiped clean, sunlight through dusty windows |
| `airport` | فرودگاه | an airport terminal at night, an empty baggage carousel, rows of seats, big dark windows with a plane outside |
| `tower` | برج | the top floor of a modern office tower at night, glass walls, the city lights far below, a stopped wall clock |

### 2.4 Character portraits (40)
- The app picks a portrait for each suspect by gender, age and role, so 40 cover all 250 suspects.
- Each prompt is: **style block + `head and shoulders portrait of` + the description + `, neutral slightly suspicious expression, plain dark navy background`**.

#### Men (20)
| code | Description |
|---|---|
| `m_young_casual` | a young Iranian man about 25, short dark hair, light stubble, casual jacket |
| `m_young_student` | a young Iranian man about 22, glasses, backpack strap, sweater |
| `m_young_worker` | a young Iranian man about 28, work overalls, short beard, tired eyes |
| `m_young_waiter` | a young Iranian man about 26, white shirt and black vest, neat hair |
| `m_mid_business` | a middle-aged Iranian businessman about 50, grey suit, trimmed grey beard |
| `m_mid_doctor` | a middle-aged Iranian doctor about 45, white coat, stethoscope, glasses |
| `m_mid_chef` | a middle-aged Iranian chef about 45, white chef jacket, strong arms, mustache |
| `m_mid_guard` | a middle-aged Iranian security guard about 40, dark uniform, cap, serious face |
| `m_mid_driver` | a middle-aged Iranian driver about 42, leather jacket, stubble |
| `m_mid_artist` | a middle-aged Iranian artist about 40, longer hair, scarf, paint on fingers |
| `m_mid_technician` | a middle-aged Iranian technician about 38, tool belt, cap backwards |
| `m_mid_teacher` | a middle-aged Iranian teacher about 48, cardigan, glasses on a cord |
| `m_mid_merchant` | a middle-aged Iranian bazaar merchant about 55, traditional vest, full beard |
| `m_mid_lawyer` | a middle-aged Iranian lawyer about 45, dark suit, briefcase, clean shaven |
| `m_old_professor` | an old Iranian professor about 68, white hair, round glasses, tweed jacket |
| `m_old_gardener` | an old Iranian gardener about 65, weathered face, simple shirt, white stubble |
| `m_old_rich` | an old wealthy Iranian man about 72, silver hair, expensive coat, cane |
| `m_young_athlete` | a young Iranian man about 24, sports jacket, athletic build |
| `m_mid_sailor` | a middle-aged Iranian sailor about 45, knit cap, sun-tanned skin, beard |
| `m_mid_officer` | a middle-aged Iranian hotel manager about 47, formal suit, name badge without text |

#### Women (20, all with hijab)
| code | Description |
|---|---|
| `f_young_student` | a young Iranian woman about 22, colorful roosari, glasses, backpack strap |
| `f_young_artist` | a young Iranian woman about 26, loose roosari, artistic scarf, earrings |
| `f_young_nurse` | a young Iranian nurse about 27, white maghnaeh, nurse uniform |
| `f_young_waitress` | a young Iranian woman about 24, dark roosari, black uniform with apron |
| `f_young_researcher` | a young Iranian woman about 29, lab coat, neat roosari, focused eyes |
| `f_mid_doctor` | a middle-aged Iranian doctor about 44, dark maghnaeh, white coat, glasses |
| `f_mid_business` | a middle-aged Iranian businesswoman about 48, elegant roosari, dark blazer |
| `f_mid_teacher` | a middle-aged Iranian teacher about 45, simple roosari, cardigan |
| `f_mid_chef` | a middle-aged Iranian chef about 42, roosari tied back, chef jacket |
| `f_mid_cleaner` | a middle-aged Iranian cleaning worker about 50, simple roosari, work smock |
| `f_mid_pharmacist` | a middle-aged Iranian pharmacist about 40, maghnaeh, white coat |
| `f_mid_manager` | a middle-aged Iranian stage manager about 43, practical roosari, headset |
| `f_mid_lawyer` | a middle-aged Iranian lawyer about 46, dark roosari, formal coat |
| `f_mid_restorer` | a middle-aged Iranian art restorer about 38, roosari, magnifier glasses on head |
| `f_mid_guest` | a middle-aged Iranian woman traveler about 40, stylish roosari, trench coat |
| `f_old_rich` | an old wealthy Iranian woman about 70, silk roosari, pearl earrings |
| `f_old_grandma` | an old Iranian grandmother about 72, chador framing her face, kind but sharp eyes |
| `f_old_shopkeeper` | an old Iranian shopkeeper about 65, dark roosari, cardigan, reading glasses |
| `f_young_athlete` | a young Iranian woman about 25, sports hijab, track jacket |
| `f_mid_officer` | a middle-aged Iranian security officer about 41, dark maghnaeh, uniform |

### 2.5 Detective avatars (12)
- These are the player's own portraits: friendlier and a little heroic.
- Use the same portrait suffix as 2.4, but with the expression **`confident calm expression`**.

| file | Description |
|---|---|
| `det_01` | a young man detective, trench coat, short hair |
| `det_02` | a young woman detective, dark roosari, trench coat |
| `det_03` | a middle-aged man detective, fedora hat, mustache |
| `det_04` | a middle-aged woman detective, maghnaeh, long coat, glasses |
| `det_05` | an old man detective, white beard, wool coat, pipe in hand (unlit) |
| `det_06` | an old woman detective, silk roosari, sharp eyes, cardigan |
| `det_07` | a young man detective, glasses, sweater, notebook |
| `det_08` | a young woman detective, sporty hijab, leather jacket |
| `det_09` | a man detective, full beard, flat cap, scarf |
| `det_10` | a woman detective, elegant roosari, magnifying glass near her face |
| `det_11` | a man detective, clean shaven, suit and tie, serious |
| `det_12` | a woman detective, colorful roosari, warm smile, raincoat |

### 2.6 Evidence-type icons (6)
- **Prompt for each:** `flat noir icon of <object>, brass and paper colors, simple shapes, centered, transparent background, no text`

| file | Object |
|---|---|
| `ev_document` | a folded paper document with a paper clip |
| `ev_cctv` | a security camera |
| `ev_phone` | a mobile phone with a glowing screen |
| `ev_forensic` | a test tube and a magnifying glass |
| `ev_receipt` | a torn paper receipt |
| `ev_object` | an evidence bag with a tag |

### 2.7 Animations (optional, free)
Download from **lottiefiles.com**:
- **Format:** Lottie **JSON**, each file under **150 KB**
- **License:** the free license (Lottie Simple License)

| file | Search for |
|---|---|
| `anim_search.json` | magnifying glass searching |
| `anim_stamp.json` | rubber stamp |
| `anim_chest.json` | treasure chest opening |
| `anim_success.json` | success check |
| `anim_fail.json` | cross / error |

Rain, fog, dust and light flicker over the scenes I'll make in code, so you don't need files for those.

### 2.8 Order of priority
If you can't do everything at once:
1. **Scene backgrounds:** players see these most.
2. **Character portraits:** you can start with 10 men and 10 women from the lists.
3. **Detective avatars.**
4. **Evidence icons and animations.**

You can send them in batches; each batch goes into the app as soon as it arrives.
