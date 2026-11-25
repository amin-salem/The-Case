// Pre-generates and verifies the «کی کجا؟» puzzle pool: node generate.js > ../../app/content/kikoja/puzzles.json
// Each puzzle keeps what the phone may see (S, locks, cast…) and `answer` (never sent before the player solves):
// thief, the one false statement, the real paths, every accepted proof (contradicting statement + witness sets), hints.
const E = require('./engine.js');
const COUNT = +process.argv[2] || 60;
const PEOPLE = ['mina', 'nasrin', 'forough', 'taraneh', 'kaveh', 'bahram', 'mansour', 'farhad'];
const OBJ = [['ساعتِ جیبی', 'ساعتِ جیبیِ طلا'], ['انگشتر', 'انگشترِ عقیقِ پدربزرگ'], ['نامه', 'نامهٔ وصیت'], ['کلید', 'کلیدِ گاوصندوق'], ['تمبر', 'آلبومِ تمبرِ قدیمی']];
const ROLES = ['مهمان', 'همسایه', 'آشپز', 'خواهرزاده', 'دوستِ قدیمی', 'نوه', 'پسرعمو', 'عکاس'];
const STORY = { qolhak: 'مهمانیِ کوچکی در خانهٔ باغِ قلهک.', kashan: 'شبِ پیش از حراج، در خانهٔ تاریخیِ کاشان.' };
const NOT_TARGET = ['court', 'hall', 'yard', 'r1', 'r2', 'r3'];
function rng(seed) { let s = (seed >>> 0) || 1; return () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; }; }
const pick = (r, a) => a[Math.floor(r() * a.length)];
function shuffle(r, a) { a = a.slice(); for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(r() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; }
function unsatSet(list, X, P) {
  const cons = []; for (const s of list) cons.push(...s.cons);
  cons.push([X, P.k, P.target, false]); for (let q = 0; q < P.n; q++) if (q !== X) cons.push([q, P.k, P.target, true]);
  return !E.feasible(cons, P.n, P.T, P.roomIds, P.nb, P.lockSet);
}
function build(i) {
  const seed = 1000 + i * 37, r = E.rng ? E.rng(seed) : rng(seed);
  const house = i % 2 ? 'kashan' : 'qolhak', hard = !(i % 3 === 0 && house === 'qolhak') && true;
  const rooms = E.HOUSES[house].rooms.map(x => x.id);
  const T = hard ? 5 : 4, n = house === 'kashan' ? (r() < 0.5 ? 5 : 6) : (hard ? 5 : 4 + Math.floor(r() * 2));
  const target = pick(r, rooms.filter(x => !NOT_TARGET.includes(x)));
  const k = 1 + Math.floor(r() * (T - 2)), obj = pick(r, OBJ);
  const ids = shuffle(r, PEOPLE).slice(0, n), roles = shuffle(r, ROLES);
  const cfg = { house, n, T, k, target, diff: hard ? 'hard' : 'medium' };
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
  const ob = obj;
  return { id: 'k' + String(i + 1).padStart(3, '0'), house, diff: hard ? 3 : 2, n, T, k, target, locks: g.locks || [],
    title: ob[1], obj: ob[0], story: `${STORY[house]} ${ob[1]} توی ${E.HOUSES[house].rooms.find(x => x.id === target).n} بود.`,
    cast: ids.map((id, j) => [id, roles[j]]), S,
    answer: { thief: g.thief, lie: g.lie, paths: g.paths, cons, hints: { time: hintTime, pair } } };
}
const out = []; let i = 0, tried = 0;
while (out.length < COUNT && tried < COUNT * 6) { const p = build(tried++); if (p) { p.id = 'k' + String(out.length + 1).padStart(3, '0'); out.push(p); } }
process.stdout.write(JSON.stringify(out));
process.stderr.write(`puzzles ${out.length}/${COUNT} (tried ${tried})\n`);
