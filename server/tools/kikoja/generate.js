const E = require('./engine.js');
// node generate.js [perLevel] > ../../app/content/kikoja/puzzles.json   (three levels; each puzzle carries `level`)
const PER = +process.argv[2] || 10;
// three women and five men, each with the portrait the page ships (tools/kikoja_page/build.py) and roles that fit his or her age
const ROLES_OF = {
  mina: ['خواهرزاده', 'همسایه', 'عکاس', 'مهمان'], nasrin: ['نوه', 'خواهرزاده', 'همسایه', 'مهمان'], taraneh: ['خواهرزاده', 'نوه', 'عکاس', 'مهمان'],
  kaveh: ['پسرعمو', 'همسایه', 'دوستِ خانواده', 'مهمان'], bahram: ['نوه', 'پسرعمو', 'خواهرزاده', 'مهمان'],
  mansour: ['دوستِ قدیمی', 'همسایه', 'پسرعمو', 'مهمان'], farhad: ['همسایه', 'پسرعمو', 'دوستِ خانواده', 'مهمان'],
  reza: ['دوستِ قدیمی', 'همسایه', 'عکاس', 'مهمان'] };
const PEOPLE = Object.keys(ROLES_OF);
const EXTRA = ['مهمان', 'آشنای خانواده', 'مهمانِ شب', 'دوستِ دوستان', 'همکارِ قدیمی'];
function assignRoles(r, ids) { const used = new Set(); return ids.map(id => { const free = shuffle(r, ROLES_OF[id].filter(x => x !== 'مهمان')).concat(shuffle(r, EXTRA)).filter(x => !used.has(x)); const role = free[0] || 'مهمان'; used.add(role); return role; }); }
// level -> house, suspects, hours, engine difficulty, id prefix, numeric difficulty (1..3)
const LEVELS = {
  easy:   { house: 'qolhak', n: 4, T: 4, diff: 'easy',   prefix: 'e', d: 1 },
  medium: { house: 'qolhak', n: 5, T: 5, diff: 'medium', prefix: 'm', d: 2 },
  hard:   { house: 'kashan', n: 6, T: 5, diff: 'hard',   prefix: 'h', d: 3 },
};
// the thing that went missing and the evening it went missing in; two lists per house (easy and medium never share a scenario)
const SCEN = {
  qolhak: [
    ['ساعتِ جیبی', 'ساعتِ جیبیِ پدربزرگ', 'شامِ تولدِ پدربزرگ در خانهٔ باغِ قلهک'],
    ['انگشتر', 'انگشترِ عقیقِ مادربزرگ', 'مهمانیِ کوچکِ عصرانه در خانهٔ باغِ قلهک'],
    ['نامه', 'نامهٔ وصیت', 'دورهمیِ خانوادگی در خانهٔ باغِ قلهک'],
    ['کلید', 'کلیدِ گاوصندوق', 'شبِ نشینیِ پاییزی در خانهٔ باغِ قلهک'],
    ['آلبومِ تمبر', 'آلبومِ تمبرِ قدیمی', 'مهمانیِ شامِ دوستانه در خانهٔ باغِ قلهک'],
    ['گردنبند', 'گردنبندِ فیروزه', 'شبِ یلدا در خانهٔ باغِ قلهک'],
    ['خودنویس', 'خودنویسِ طلاییِ سردبیر', 'جشنِ انتشارِ کتاب در خانهٔ باغِ قلهک'],
    ['دفتر', 'دفترچهٔ حسابِ قدیمی', 'جلسهٔ خانوادگیِ آخرِ هفته در خانهٔ باغِ قلهک'],
    ['مدال', 'مدالِ افتخارِ جدّ', 'شبِ بزرگداشتِ جدّ در خانهٔ باغِ قلهک'],
    ['جعبهٔ موسیقی', 'جعبهٔ موسیقیِ عتیقه', 'مهمانیِ تولدِ کودکان در خانهٔ باغِ قلهک'],
    ['سند', 'سندِ زمینِ باغ', 'گردهماییِ وارثان در خانهٔ باغِ قلهک'],
    ['دوربین', 'دوربینِ قدیمیِ عکاس', 'نمایشِ عکس در خانهٔ باغِ قلهک'],
    ['سکه', 'سکهٔ طلایِ کمیاب', 'شبِ بازدیدِ کلکسیونرها در خانهٔ باغِ قلهک'],
    ['قاب', 'قابِ نقرهٔ عکسِ خانوادگی', 'مهمانیِ سالگردِ ازدواج در خانهٔ باغِ قلهک'],
    ['پاکت', 'پاکتِ پولِ اجاره', 'شبِ تسویه‌حساب در خانهٔ باغِ قلهک'],
    ['النگو', 'النگوی عروس', 'شبِ حنابندان در خانهٔ باغِ قلهک'],
    ['قلمدان', 'قلمدانِ نقاشی‌شده', 'شبِ شعر در خانهٔ باغِ قلهک'],
    ['ساعتِ مچی', 'ساعتِ مچیِ جدّ', 'شامِ بازنشستگیِ عمو در خانهٔ باغِ قلهک'],
    ['گوشواره', 'گوشوارهٔ مروارید', 'جشنِ فارغ‌التحصیلی در خانهٔ باغِ قلهک'],
    ['کتابچه', 'کتابچهٔ یادداشتِ مادربزرگ', 'شبِ یادبودِ مادربزرگ در خانهٔ باغِ قلهک'],
  ],
  kashan: [
    ['سینیِ نقره', 'سینیِ نقرهٔ قاجاری', 'شبِ پیش از حراج در خانهٔ تاریخیِ کاشان'],
    ['قلمدان', 'قلمدانِ لاکی', 'شبِ بازدیدِ کارشناسان در خانهٔ تاریخیِ کاشان'],
    ['فرمان', 'فرمانِ قدیمی', 'شبِ افتتاحِ موزه در خانهٔ تاریخیِ کاشان'],
    ['آینه', 'آینهٔ دست‌سازِ مرصع', 'مهمانیِ شامِ حراج در خانهٔ تاریخیِ کاشان'],
    ['گلدان', 'گلدانِ کاشیِ هفت‌رنگ', 'شبِ مرمت در خانهٔ تاریخیِ کاشان'],
    ['زنجیر', 'زنجیرِ طلایِ ساعت', 'شبِ ارزیابیِ میراث در خانهٔ تاریخیِ کاشان'],
    ['مُهر', 'مُهرِ دیوانیِ قدیمی', 'شبِ گردهماییِ وارثان در خانهٔ تاریخیِ کاشان'],
    ['دستنویس', 'دستنویسِ خطی', 'شبِ رونمایی در خانهٔ تاریخیِ کاشان'],
    ['خنجر', 'خنجرِ قدیمیِ قاب‌گرفته', 'شبِ بازدیدِ مجموعه‌داران در خانهٔ تاریخیِ کاشان'],
    ['بقچه', 'بقچهٔ ترمهٔ عروس', 'شبِ مراسمِ سالگرد در خانهٔ تاریخیِ کاشان'],
  ],
};
const NOT_TARGET = ['court', 'hall', 'yard', 'r1', 'r2', 'r3'];
function rng(seed) { let s = (seed >>> 0) || 1; return () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; }; }
const pick = (r, a) => a[Math.floor(r() * a.length)];
function shuffle(r, a) { a = a.slice(); for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(r() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; }
function unsatSet(list, X, P) {
  const cons = []; for (const s of list) cons.push(...s.cons);
  cons.push([X, P.k, P.target, false]); for (let q = 0; q < P.n; q++) if (q !== X) cons.push([q, P.k, P.target, true]);
  return !E.feasible(cons, P.n, P.T, P.roomIds, P.nb, P.lockSet);
}
function build(level, i, tried) {
  const LV = LEVELS[level], seed = 1000 + tried * 37 + LV.d * 7919, r = E.rng ? E.rng(seed) : rng(seed);
  for (let w = 0; w < 12; w++) r();   // warm up: neighbouring seeds must not make the same first picks
  const house = LV.house, rooms = E.HOUSES[house].rooms.map(x => x.id);
  const T = LV.T, n = LV.n;
  const target = pick(r, rooms.filter(x => !NOT_TARGET.includes(x)));
  const k = 1 + Math.floor(r() * (T - 2));
  const list = SCEN[house], base = house === 'qolhak' && level === 'medium' ? 10 : 0;
  const ob = list[(base + i) % list.length];
  const ids = shuffle(r, PEOPLE).slice(0, n), roles = assignRoles(r, ids);
  const cfg = { house, n, T, k, target, diff: LV.diff };
  const g = E.generate(cfg, seed); if (!g) return null;
  const P = E.ctx(g);
  // the engine favours low person numbers as thief: relabel the people at random so the order says nothing
  const perm = shuffle(r, [...Array(n).keys()]), mp = x => (x >= 0 ? perm[x] : x);
  const S = g.S.map(s => { const c = Object.assign({}, s); c.p = mp(s.p); if (s.y != null) c.y = mp(s.y); if (s.ys) c.ys = s.ys.map(mp); c.cons = s.cons.map(([q, ...rest]) => [mp(q), ...rest]); return c; });
  const paths = []; g.paths.forEach((pa, old) => { paths[perm[old]] = pa; }); g.paths = paths; g.thief = perm[g.thief]; g.S = S;
  const Pn = E.ctx(g); Object.assign(P, Pn);
  if (E.suspects(S, P).join() !== String(g.thief)) return null;
  for (const s of S) if (s.id !== g.lie && !E.trueOf(s, g.paths)) return null;
  const L = S.find(s => s.id === g.lie);
  if (E.trueOf(L, g.paths)) return null;
  const cons = {};
  for (const c of S) {
    if (c.id === L.id || c.p === g.thief || !E.pairUnsat(L, c, P)) continue;
    if (c.p < 0 || unsatSet([L], c.p, P)) { cons[c.id] = []; continue; }          // fact, or the rule alone clears the speaker
    const others = S.filter(s => s.p !== c.p && s.id !== L.id), wits = [];
    for (let a = 0; a < others.length; a++) {
      if (unsatSet([L, others[a]], c.p, P)) wits.push([others[a].id]);
      for (let b = a + 1; b < others.length; b++) if (unsatSet([L, others[a], others[b]], c.p, P)) wits.push([others[a].id, others[b].id]);
    }
    if (wits.length) cons[c.id] = wits;
  }
  if (!Object.keys(cons).length) return null;
  const hintTime = L.t != null && L.kind !== 'never' ? L.t : g.k;
  const c0 = S.find(s => s.p >= 0 && s.p !== g.thief && E.pairUnsat(L, s, P));
  const pair = (seed % 2) ? [g.thief, c0.p] : [c0.p, g.thief];
  return { id: LV.prefix + String(i + 1).padStart(3, '0'), level, house, diff: LV.d, n, T, k, target, locks: g.locks || [],
    title: ob[1], obj: ob[0], story: `${ob[2]}. ${ob[1]} توی ${E.HOUSES[house].rooms.find(x => x.id === target).n} بود.`,
    cast: ids.map((id, j) => [id, roles[j]]), S,
    answer: { thief: g.thief, lie: g.lie, paths: g.paths, cons, hints: { time: hintTime, pair } } };
}
const out = [];
for (const level of Object.keys(LEVELS)) {
  let made = 0, tried = 0;
  while (made < PER && tried < PER * 60) { const p = build(level, made, tried++); if (p) { out.push(p); made++; } }
  process.stderr.write(`${level}: ${made}/${PER} (tried ${tried})\n`);
}
process.stdout.write(JSON.stringify(out));
