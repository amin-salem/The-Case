# Portrait & place prompt kit v2 (Amin, 24 Oct 2026)

Why: 297 suspects share only 48 faces, and 5 suspects have no portrait file at all, so the album shows the same face under different names.
Goal of this kit: (A) fill the 5 holes, (B) add 70 new, clearly different faces, (C) add scene variants and new places.

## How to use (same rules as docs/portrait-prompts.md)
- One prompt per message, all in ONE ChatGPT chat (style stays the same). If an image drifts, reply: *same style as the first image*.
- Rename the file to the name above the prompt; keep `.png`; send them to Claude a few at a time.
- Every prompt has its own small face feature (eyes, jaw, scar...) and alternating light side, so two cards rarely look alike.
- New files are NOT used until Claude assigns them to suspects in the case JSON (matching role, age and gender). Nothing breaks if you only send some.

## A. The 5 missing portraits (do these first)
### 1. `m_young_researcher.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 33-year-old Iranian man, assistant professor of archaeology, short dark hair, round wire glasses, clean-shaven, corduroy jacket over a shirt, tired eyes, slight proud smile. Plain dark navy background. No text, no logos.
```

### 2. `m_mid_researcher.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 46-year-old Iranian man, visiting manuscript scholar, short salt-and-pepper hair, thick mustache, rectangular glasses, tweed jacket and knitted tie, calm but evasive look. Plain dark navy background. No text, no logos.
```

### 3. `f_mid_librarian.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 36-year-old Iranian woman, rare-manuscripts librarian, dark headscarf worn loosely, no glasses, cardigan and white blouse, attentive careful look, a pencil behind her ear. Plain dark navy background. No text, no logos.
```

### 4. `m_mid_worker.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 36-year-old Iranian man, hotel floor cleaner and maintenance worker, short hair, stubble, grey work uniform, sleeves rolled, tired but watchful look. Plain dark navy background. No text, no logos.
```

### 5. `f_mid_waitress.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 32-year-old Iranian woman, hotel room-service and restaurant attendant, dark headscarf, neat black uniform with white collar, composed polite look hiding unease. Plain dark navy background. No text, no logos.
```

## B1. New men (34)
### 1. `m_young_courier.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 24-year-old Iranian motorbike courier, messy black hair, thin beard, helmet strap hanging at his neck, windbreaker, restless eyes, narrow face. Plain dark navy background. No text, no logos.
```

### 2. `m_young_barista.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 27-year-old Iranian barista, curly brown hair, trimmed beard, canvas apron over a flannel shirt, friendly crooked smile, round face. Plain dark navy background. No text, no logos.
```

### 3. `m_young_mechanic.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 29-year-old Iranian car mechanic, buzz cut, grease smudge on his cheek, dark overalls, defiant stare, strong jaw. Plain dark navy background. No text, no logos.
```

### 4. `m_young_photographer.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 31-year-old Iranian photographer, shoulder-length wavy hair, scarf, camera strap across his chest, curious sideways glance, long nose. Plain dark navy background. No text, no logos.
```

### 5. `m_young_lawyer.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 28-year-old Iranian junior lawyer, slicked-back hair, sharp jaw, slim suit, loosened tie, over-confident smirk, prominent cheekbones. Plain dark navy background. No text, no logos.
```

### 6. `m_young_musician.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 26-year-old Iranian musician, long dark curls, thin mustache, open-collar shirt, dreamy distant eyes, freckles. Plain dark navy background. No text, no logos.
```

### 7. `m_young_soldier.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 23-year-old Iranian conscript soldier, shaved head, olive uniform collar, big ears, anxious honest face, a small scar near the lip. Plain dark navy background. No text, no logos.
```

### 8. `m_young_chef.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 25-year-old Iranian line cook, hair under a bandana, light beard, chef jacket with burn marks on the sleeve, cocky grin, dimples. Plain dark navy background. No text, no logos.
```

### 9. `m_young_vendor.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 22-year-old Iranian street vendor, tousled hair, wool cap, fingerless gloves, cheerful but sly look, heavy eyelids. Plain dark navy background. No text, no logos.
```

### 10. `m_young_diplomat.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 30-year-old Iranian junior diplomat, neat side parting, round face, grey suit, rigid polite expression, thick eyebrows. Plain dark navy background. No text, no logos.
```

### 11. `m_mid_baker.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 41-year-old Iranian baker, heavy build, flour on his forearms and eyebrows, white undershirt, warm tired eyes, a gap in the front teeth. Plain dark navy background. No text, no logos.
```

### 12. `m_mid_journalist.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 38-year-old Iranian journalist, unkempt hair, three-day beard, creased linen jacket, press card on a lanyard, sharp skeptical look, wide-set eyes. Plain dark navy background. No text, no logos.
```

### 13. `m_mid_pilot.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 44-year-old Iranian airline pilot, grey temples, clean-shaven, white uniform shirt with epaulettes, steady controlled gaze, narrow face. Plain dark navy background. No text, no logos.
```

### 14. `m_mid_engineer.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 39-year-old Iranian site engineer, short hair, safety helmet pushed back, reflective vest, sunburnt nose, impatient look, round face. Plain dark navy background. No text, no logos.
```

### 15. `m_mid_priest.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 50-year-old Iranian clergyman, dark turban, short grey beard, plain dark robe, gentle but unreadable expression, strong jaw. Plain dark navy background. No text, no logos.
```

### 16. `m_mid_accountant.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 47-year-old Iranian accountant, thinning hair, thick square glasses, grey cardigan, pen in the pocket, nervous exact manner, long nose. Plain dark navy background. No text, no logos.
```

### 17. `m_mid_butcher.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 43-year-old Iranian butcher, broad shoulders, big mustache, stained white apron, blunt direct stare, prominent cheekbones. Plain dark navy background. No text, no logos.
```

### 18. `m_mid_tailor.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 52-year-old Iranian tailor, balding with grey sides, half-moon glasses, measuring tape around his neck, patient watchful eyes, freckles. Plain dark navy background. No text, no logos.
```

### 19. `m_mid_cop.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 37-year-old Iranian plainclothes detective, short wavy hair, square jaw, leather jacket, tired suspicious eyes, a small scar near the lip. Plain dark navy background. No text, no logos.
```

### 20. `m_mid_gambler.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 42-year-old Iranian man with a gambler's air, slicked hair, thin mustache, loud patterned shirt under a blazer, gold ring, restless smile, dimples. Plain dark navy background. No text, no logos.
```

### 21. `m_mid_translator.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 40-year-old Iranian translator, soft features, round glasses, scarf, ink on his fingers, shy evasive look, heavy eyelids. Plain dark navy background. No text, no logos.
```

### 22. `m_mid_farmer.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 48-year-old Iranian farmer, weathered face, deep wrinkles, thick eyebrows, wool vest, quiet stubborn stare, thick eyebrows. Plain dark navy background. No text, no logos.
```

### 23. `m_mid_banker.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 45-year-old Iranian bank manager, immaculate grey hair, rimless glasses, dark three-piece suit, cold polite smile, a gap in the front teeth. Plain dark navy background. No text, no logos.
```

### 24. `m_mid_actor.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 43-year-old Iranian stage actor, dramatic cheekbones, swept-back hair with silver streaks, black turtleneck, theatrical wounded expression, wide-set eyes. Plain dark navy background. No text, no logos.
```

### 25. `m_old_jeweler.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 66-year-old Iranian jeweler, white hair, neat white beard, loupe on a cord, waistcoat, shrewd narrow eyes, narrow face. Plain dark navy background. No text, no logos.
```

### 26. `m_old_retired_judge.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 70-year-old Iranian retired judge, bald, deep-set eyes, grey mustache, formal dark coat, severe stillness, round face. Plain dark navy background. No text, no logos.
```

### 27. `m_old_fisherman.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 64-year-old Iranian fisherman, sun-cracked skin, white stubble, knitted cap, thick sweater, squinting calm eyes, strong jaw. Plain dark navy background. No text, no logos.
```

### 28. `m_old_bookseller.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 68-year-old Iranian bookseller, wild white hair, spectacles on his forehead, wool scarf, mischievous knowing smile, long nose. Plain dark navy background. No text, no logos.
```

### 29. `m_old_caretaker.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 72-year-old Iranian building caretaker, thin face, hollow cheeks, flat cap, buttoned old jacket, wary eyes, prominent cheekbones. Plain dark navy background. No text, no logos.
```

### 30. `m_old_general.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 69-year-old Iranian retired officer, white mustache, straight posture, medals-ribbon bar on a plain jacket, proud hard look, freckles. Plain dark navy background. No text, no logos.
```

### 31. `m_old_clockmaker.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 74-year-old Iranian clockmaker, magnifier glass over one eye, bald head, tiny round glasses, apron, absorbed expression, a small scar near the lip. Plain dark navy background. No text, no logos.
```

### 32. `m_old_tea_seller.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 67-year-old Iranian teahouse owner, round face, big white mustache, embroidered vest, kind but secretive smile, dimples. Plain dark navy background. No text, no logos.
```

### 33. `m_old_mullah_neighbor.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 71-year-old Iranian man, long white beard, white skullcap, brown cloak, deep tired eyes, heavy eyelids. Plain dark navy background. No text, no logos.
```

### 34. `m_old_gangster.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 63-year-old Iranian former smuggler, scar across the eyebrow, grey slicked hair, expensive overcoat, calm menacing smile, thick eyebrows. Plain dark navy background. No text, no logos.
```

## B2. New women (36)
### 1. `f_young_journalist.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 27-year-old Iranian woman journalist, loose dark headscarf, trench coat, notebook in hand, sharp curious eyes, narrow face. Plain dark navy background. No text, no logos.
```

### 2. `f_young_barista.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 24-year-old Iranian woman barista, hair in a messy bun, apron, nose stud, tired friendly smile, round face. Plain dark navy background. No text, no logos.
```

### 3. `f_young_dancer.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 26-year-old Iranian woman dancer, hair pulled tight, long neck, plain black top, proud guarded posture, strong jaw. Plain dark navy background. No text, no logos.
```

### 4. `f_young_engineer.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 29-year-old Iranian woman engineer, short bob, round glasses, work shirt, pencil behind her ear, focused look, long nose. Plain dark navy background. No text, no logos.
```

### 5. `f_young_model.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 25-year-old Iranian woman fashion model, high cheekbones, long dark hair, bold lipstick, cold bored stare, prominent cheekbones. Plain dark navy background. No text, no logos.
```

### 6. `f_young_lawyer.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 30-year-old Iranian woman lawyer, dark headscarf, tailored blazer, composed determined expression, freckles. Plain dark navy background. No text, no logos.
```

### 7. `f_young_musician.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 28-year-old Iranian woman violinist, wavy hair to her shoulders, black dress, dreamy but tense look, a small scar near the lip. Plain dark navy background. No text, no logos.
```

### 8. `f_young_courier.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 23-year-old Iranian woman delivery rider, short cropped hair, bright jacket, wind-flushed cheeks, defiant grin, dimples. Plain dark navy background. No text, no logos.
```

### 9. `f_young_bride.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 26-year-old Iranian woman in a pale veil and simple bridal dress, smudged eyeliner, frightened eyes, heavy eyelids. Plain dark navy background. No text, no logos.
```

### 10. `f_young_mechanic.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 31-year-old Iranian woman mechanic, hair tied in a bandana, grease on her cheek, overalls, confident smirk, thick eyebrows. Plain dark navy background. No text, no logos.
```

### 11. `f_young_pharmacist.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 27-year-old Iranian woman pharmacy assistant, headscarf, white coat, careful polite smile, a gap in the front teeth. Plain dark navy background. No text, no logos.
```

### 12. `f_young_influencer.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 24-year-old Iranian woman social-media influencer, glossy wavy hair, hoop earrings, ring light reflected in her eyes, practiced smile, wide-set eyes. Plain dark navy background. No text, no logos.
```

### 13. `f_mid_novelist.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 44-year-old Iranian woman novelist, grey-streaked hair in a loose knot, big glasses, shawl, wry knowing look, narrow face. Plain dark navy background. No text, no logos.
```

### 14. `f_mid_judge.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 49-year-old Iranian woman judge, dark headscarf, dark formal coat, stern composed face, round face. Plain dark navy background. No text, no logos.
```

### 15. `f_mid_surgeon.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 42-year-old Iranian woman surgeon, surgical cap, mask pulled down, sharp tired eyes, strong jaw. Plain dark navy background. No text, no logos.
```

### 16. `f_mid_accountant.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 46-year-old Iranian woman accountant, hair in a tight bun, cat-eye glasses, cardigan, meticulous guarded expression, long nose. Plain dark navy background. No text, no logos.
```

### 17. `f_mid_tailor.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 51-year-old Iranian woman seamstress, pins in her collar, glasses on a chain, strong forearms, patient measuring eyes, prominent cheekbones. Plain dark navy background. No text, no logos.
```

### 18. `f_mid_actress.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 40-year-old Iranian actress, dramatic dark eyes, elegant scarf, faded stage makeup, wounded pride, freckles. Plain dark navy background. No text, no logos.
```

### 19. `f_mid_pilot.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 38-year-old Iranian woman flight attendant, neat scarf and uniform jacket, immaculate smile that does not reach her eyes, a small scar near the lip. Plain dark navy background. No text, no logos.
```

### 20. `f_mid_cook.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 47-year-old Iranian woman restaurant cook, headscarf, apron, flushed face, strong honest stare, dimples. Plain dark navy background. No text, no logos.
```

### 21. `f_mid_widow.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 45-year-old Iranian widow, black scarf, no makeup, red-rimmed eyes, rigid dignified mouth, heavy eyelids. Plain dark navy background. No text, no logos.
```

### 22. `f_mid_police.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 36-year-old Iranian policewoman, dark uniform scarf and cap, serious steady look, thick eyebrows. Plain dark navy background. No text, no logos.
```

### 23. `f_mid_gallery.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 41-year-old Iranian gallery owner, asymmetric haircut, large earrings, black blazer, cool appraising gaze, a gap in the front teeth. Plain dark navy background. No text, no logos.
```

### 24. `f_mid_driver.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 39-year-old Iranian taxi driver, short hair, sunglasses pushed up on her head, leather jacket, wry half smile, wide-set eyes. Plain dark navy background. No text, no logos.
```

### 25. `f_mid_scientist.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 43-year-old Iranian woman chemist, safety glasses on her forehead, white lab coat, brisk intelligent look, narrow face. Plain dark navy background. No text, no logos.
```

### 26. `f_mid_hairdresser.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 37-year-old Iranian hairdresser, voluminous hair, bright earrings, black smock, gossipy conspiratorial smile, round face. Plain dark navy background. No text, no logos.
```

### 27. `f_old_widow_rich.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 68-year-old Iranian woman, silver hair, pearl necklace, elegant dark dress, cold aristocratic stare, strong jaw. Plain dark navy background. No text, no logos.
```

### 28. `f_old_midwife.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 71-year-old Iranian woman, white scarf, wrinkled kind face, strong tired hands folded in front, steady eyes, long nose. Plain dark navy background. No text, no logos.
```

### 29. `f_old_seamstress.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 66-year-old Iranian woman, grey hair under a floral scarf, thick glasses, needle in her lapel, sharp gentle look, prominent cheekbones. Plain dark navy background. No text, no logos.
```

### 30. `f_old_professor.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 69-year-old Iranian woman professor, short white hair, large glasses, wool blazer, severe intelligent gaze, freckles. Plain dark navy background. No text, no logos.
```

### 31. `f_old_neighbor.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 73-year-old Iranian woman neighbor, patterned scarf, shawl, curious bright eyes, small suspicious frown, a small scar near the lip. Plain dark navy background. No text, no logos.
```

### 32. `f_old_singer.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 67-year-old Iranian former singer, dyed dark hair, heavy earrings, faded glamour, proud wistful smile, dimples. Plain dark navy background. No text, no logos.
```

### 33. `f_old_farmer.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 65-year-old Iranian village woman, colorful scarf, sun-lined face, calloused hands, quiet stubborn look, heavy eyelids. Plain dark navy background. No text, no logos.
```

### 34. `f_old_housekeeper.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 62-year-old Iranian housekeeper, white scarf, apron, tired watchful eyes, lips pressed tight, thick eyebrows. Plain dark navy background. No text, no logos.
```

### 35. `f_old_fortune.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the left, deep navy shadows, subtle film grain. Head and shoulders of a 70-year-old Iranian woman, dark scarf with beads, deep-set eyes, cup-reader's mysterious half smile, a gap in the front teeth. Plain dark navy background. No text, no logos.
```

### 36. `f_old_judge_widow.png`
```
Square 1024x1024 portrait. Moody noir painterly illustration, cinematic warm amber light from the right, deep navy shadows, subtle film grain. Head and shoulders of a 64-year-old Iranian woman, grey bob, black coat, brooch, grief held under control, wide-set eyes. Plain dark navy background. No text, no logos.
```

## C1. Scene variants of our 20 places (second look, `_b`)
### 1. `airport_b.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A late-night airport terminal: empty gate seats, a closed check-in desk, wet floor reflecting departure-board glow, different angle and composition from the standard version. No people, no text, no logos.
```

### 2. `bazaar_night_b.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A covered iranian bazaar at night: shuttered stalls, one lamp still lit over spice sacks, long brick vaults, different angle and composition from the standard version. No people, no text, no logos.
```

### 3. `desert_b.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A desert road at dusk: a broken-down truck, long shadows, a distant ridge, cold blue sky over orange sand, different angle and composition from the standard version. No people, no text, no logos.
```

### 4. `harbor_b.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A fishing harbor before dawn: wooden boats, coiled ropes, a single lantern, mist on black water, different angle and composition from the standard version. No people, no text, no logos.
```

### 5. `hospital_b.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A hospital corridor at 3 a.m.: green-tinted light, a gurney against the wall, one door ajar, different angle and composition from the standard version. No people, no text, no logos.
```

### 6. `hotel_b.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A grand old hotel lobby after midnight: reception desk, brass bell, velvet armchairs, a stairway into shadow, different angle and composition from the standard version. No people, no text, no logos.
```

### 7. `kitchen_b.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A restaurant kitchen after closing: steel counters, hanging pans, steam, one open walk-in fridge door, different angle and composition from the standard version. No people, no text, no logos.
```

### 8. `lab_b.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A university chemistry lab at night: glassware, a fume hood glowing, papers scattered on a bench, different angle and composition from the standard version. No people, no text, no logos.
```

### 9. `library_b.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. An old reading room: tall shelves, a green reading lamp, a ladder, a book left open on a table, different angle and composition from the standard version. No people, no text, no logos.
```

### 10. `museum_b.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A museum gallery after hours: a lit empty display case, ropes, a painting in shadow, polished floor, different angle and composition from the standard version. No people, no text, no logos.
```

### 11. `office_b.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. An open-plan office at night: blinking monitors, a glass meeting room, one desk lamp, scattered files, different angle and composition from the standard version. No people, no text, no logos.
```

### 12. `school_b.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. An empty school corridor: lockers, a chalkboard in an open classroom, moonlight through tall windows, different angle and composition from the standard version. No people, no text, no logos.
```

### 13. `snow_lodge_b.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A mountain lodge in a snowstorm: a fireplace, wooden beams, snow against the window, boots by the door, different angle and composition from the standard version. No people, no text, no logos.
```

### 14. `subway_b.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A subway platform at night: tiled walls, a last train's red lights, a lone bench, a dropped bag, different angle and composition from the standard version. No people, no text, no logos.
```

### 15. `theater_b.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A theater stage after the show: curtains half open, a prop chair, a single ghost light, different angle and composition from the standard version. No people, no text, no logos.
```

### 16. `tower_b.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A high-rise rooftop: city lights below, a water tank, antennas, wind-blown plastic sheet, different angle and composition from the standard version. No people, no text, no logos.
```

### 17. `train_b.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A night train compartment: narrow corridor, curtain drawn, a suitcase on the rack, passing lights outside, different angle and composition from the standard version. No people, no text, no logos.
```

### 18. `villa_rain_b.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A walled villa garden in the rain: a lit study window, wet roses, a pool with ripples, stone path, different angle and composition from the standard version. No people, no text, no logos.
```

### 19. `warehouse_b.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A customs warehouse: stacked crates, a forklift, a swinging bulb, a stenciled box opened, different angle and composition from the standard version. No people, no text, no logos.
```

### 20. `wedding_b.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A wedding hall after the guests have left: long tables, wilted flowers, a cake cut unevenly, fallen confetti, different angle and composition from the standard version. No people, no text, no logos.
```

## C2. 12 new places
### 21. `mosque_courtyard.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A quiet mosque courtyard at night: a tiled pool reflecting a lit dome, empty prayer rugs. No people, no text, no logos.
```

### 22. `caravanserai.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A ruined caravanserai in the desert: arches, a campfire dying, saddlebags. No people, no text, no logos.
```

### 23. `tea_house.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. An old iranian tea house after closing: samovar, low tables, patterned rugs, steam. No people, no text, no logos.
```

### 24. `pharmacy.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A small-town pharmacy at night: glass jars, a neon cross, a prescription pad on the counter. No people, no text, no logos.
```

### 25. `car_park.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. An underground car park: concrete pillars, flickering tube light, a single parked car with its door open. No people, no text, no logos.
```

### 26. `rooftop_pool.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A hotel rooftop pool at night: empty loungers, blue underwater glow, a towel left behind. No people, no text, no logos.
```

### 27. `fishmarket.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A fish market at 5 a.m.: ice, crates, wet tiles, hanging scales. No people, no text, no logos.
```

### 28. `press_room.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A newspaper office at night: typewriter-era desks, cork board with photos and strings, cold coffee. No people, no text, no logos.
```

### 29. `cinema.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. An old cinema auditorium: rows of red seats, the projector beam through dust, a forgotten coat. No people, no text, no logos.
```

### 30. `clinic_garden.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A clinic courtyard garden: bench, fountain, hedges, fog. No people, no text, no logos.
```

### 31. `gym.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A boxing gym at night: heavy bags, a ring under one lamp, a locker left open. No people, no text, no logos.
```

### 32. `ferry.png`
```
Square 1024x1024 illustration (same size as our current scenes). Moody noir painterly illustration, cinematic warm amber light, deep navy shadows, subtle film grain. A ferry deck in fog: railings, lifebelts, a lone bench, foghorn glow. No people, no text, no logos.
```

