// «نقشهٔ آن شب» — puzzle engine (pure; runs in the page and in node for tests)
const HOUSES = {
  qolhak: { name: 'خانهٔ باغِ قلهک', w: 300, h: 200, rooms: [
    { id: 'lib', n: 'کتابخانه', s: 'کتابخونه', x: 200, y: 0, w: 100, h: 100 },
    { id: 'salon', n: 'سالن', s: 'سالن', x: 100, y: 0, w: 100, h: 100 },
    { id: 'yard', n: 'حیاط', s: 'حیاط', x: 0, y: 0, w: 100, h: 100 },
    { id: 'study', n: 'اتاق کار', s: 'اتاق کار', x: 200, y: 100, w: 100, h: 100 },
    { id: 'hall', n: 'راهرو', s: 'راهرو', x: 100, y: 100, w: 100, h: 100 },
    { id: 'kitchen', n: 'آشپزخانه', s: 'آشپزخونه', x: 0, y: 100, w: 100, h: 100 } ],
    doors: [['lib','salon'],['salon','yard'],['salon','hall'],['lib','study'],['study','hall'],['hall','kitchen'],['kitchen','yard']] },
  kashan: { name: 'خانهٔ تاریخیِ کاشان', w: 300, h: 300, rooms: [
    { id: 'upper', n: 'بالاخانه', s: 'بالاخونه', x: 200, y: 0, w: 100, h: 100 },
    { id: 'porch', n: 'ایوان', s: 'ایوون', x: 100, y: 0, w: 100, h: 100 },
    { id: 'shah', n: 'شاه‌نشین', s: 'شاه‌نشین', x: 0, y: 0, w: 100, h: 100 },
    { id: 'kitchen', n: 'مطبخ', s: 'مطبخ', x: 200, y: 100, w: 100, h: 100 },
    { id: 'court', n: 'حیاط و حوض', s: 'حیاط', x: 100, y: 100, w: 100, h: 100 },
    { id: 'lib', n: 'کتابخانه', s: 'کتابخونه', x: 0, y: 100, w: 100, h: 100 },
    { id: 'store', n: 'انبار', s: 'انبار', x: 200, y: 200, w: 100, h: 100 },
    { id: 'hashti', n: 'هشتی', s: 'هشتی', x: 100, y: 200, w: 100, h: 100 },
    { id: 'guest', n: 'اتاق مهمان', s: 'اتاق مهمون', x: 0, y: 200, w: 100, h: 100 } ],
    doors: [['upper','porch'],['porch','shah'],['porch','court'],['court','kitchen'],['court','lib'],['court','hashti'],['kitchen','store'],['store','hashti'],['hashti','guest'],['lib','guest']] },
  train: { name: 'قطارِ شبِ مشهد', w: 500, h: 200, rooms: [
    { id: 'diner', n: 'رستوران', s: 'رستوران', x: 400, y: 0, w: 100, h: 200 },
    { id: 'c1', n: 'کوپهٔ ۱', s: 'کوپهٔ یک', x: 300, y: 0, w: 100, h: 110 },
    { id: 'c2', n: 'کوپهٔ ۲', s: 'کوپهٔ دو', x: 200, y: 0, w: 100, h: 110 },
    { id: 'c3', n: 'کوپهٔ ۳', s: 'کوپهٔ سه', x: 100, y: 0, w: 100, h: 110 },
    { id: 'c4', n: 'کوپهٔ ۴', s: 'کوپهٔ چهار', x: 0, y: 0, w: 100, h: 110 },
    { id: 'r1', n: 'راهرو', s: 'راهروی جلو', x: 300, y: 110, w: 100, h: 90 },
    { id: 'r2', n: 'راهرو', s: 'راهروی وسط', x: 200, y: 110, w: 100, h: 90 },
    { id: 'r3', n: 'راهرو', s: 'راهروی عقب', x: 100, y: 110, w: 100, h: 90 },
    { id: 'bag', n: 'واگنِ بار', s: 'واگنِ بار', x: 0, y: 110, w: 100, h: 90 } ],
    doors: [['diner','r1'],['r1','c1'],['r2','c2'],['r3','c3'],['bag','c4'],['r1','r2'],['r2','r3'],['r3','bag']] },
};

function rng(seed) { let s = (seed >>> 0) || 1; return () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; }; }
const pick = (r, a) => a[Math.floor(r() * a.length)];
function shuffle(r, a) { a = a.slice(); for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(r() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; }

function neighbours(house) {
  const nb = {}; for (const r of house.rooms) nb[r.id] = new Set([r.id]);
  for (const [a, b] of house.doors) { nb[a].add(b); nb[b].add(a); }
  return nb;
}

// cons: [person, slot, room, negative]
function feasible(cons, n, T, rooms, nb, locks) {
  for (let p = 0; p < n; p++) {
    const allow = []; let any = false;
    for (let t = 0; t < T; t++) allow.push(null);
    for (const [q, t, r, neg] of cons) if (q === p) { any = true; if (!allow[t]) allow[t] = { pos: new Set(), neg: new Set() }; (neg ? allow[t].neg : allow[t].pos).add(r); }
    if (!any) continue;
    let reach = null;
    for (let t = 0; t < T; t++) {
      let set;
      const a = allow[t];
      if (a && a.pos.size > 1) return false;
      if (a && a.pos.size === 1) set = new Set(a.pos); else set = new Set(rooms);
      if (a) for (const r of a.neg) set.delete(r);
      if (reach) { const nx = new Set(); for (const r of set) { for (const q of reach) if (nb[q].has(r) && !(locks && q !== r && locks.has(q + '|' + r + '|' + (t - 1)))) { nx.add(r); break; } } set = nx; }
      if (!set.size) return false;
      reach = set;
    }
  }
  return true;
}

function candidateOK(X, S, P) {
  const cons = [];
  for (const s of S) if (s.p !== X) cons.push(...s.cons);
  cons.push([X, P.k, P.target, false]);
  for (let q = 0; q < P.n; q++) if (q !== X) cons.push([q, P.k, P.target, true]);
  return feasible(cons, P.n, P.T, P.roomIds, P.nb, P.lockSet);
}
function pairUnsat(a, b, P) { return !feasible(a.cons.concat(b.cons), P.n, P.T, P.roomIds, P.nb, P.lockSet); }
function lockSetOf(locks) { const s = new Set(); for (const [a, b, t] of locks) { s.add(a + '|' + b + '|' + t); s.add(b + '|' + a + '|' + t); } return s; }
function trueOf(s, paths) { return s.cons.every(([p, t, r, neg]) => (paths[p][t] === r) !== neg); }
function suspects(S, P) { const out = []; for (let x = 0; x < P.n; x++) if (candidateOK(x, S, P)) out.push(x); return out; }

// every true thing person i can say
function truthPool(i, paths, P) {
  const out = [], n = P.n, T = P.T;
  for (let t = 0; t < T; t++) {
    const R = paths[i][t];
    const W = []; for (let q = 0; q < n; q++) if (q !== i && paths[q][t] === R) W.push(q);
    out.push({ p: i, kind: 'self', t, r: R, cons: [[i, t, R, false]] });
    if (!W.length) { const c = [[i, t, R, false]]; for (let q = 0; q < n; q++) if (q !== i) c.push([q, t, R, true]); out.push({ p: i, kind: 'alone', t, r: R, cons: c }); }
    for (const y of W) out.push({ p: i, kind: 'saw', t, r: R, y, cons: [[i, t, R, false], [y, t, R, false]] });
    if (W.length === 1) { const y = W[0]; const c = [[i, t, R, false], [y, t, R, false]]; for (let q = 0; q < n; q++) if (q !== i && q !== y) c.push([q, t, R, true]); out.push({ p: i, kind: 'only', t, r: R, y, cons: c }); }
    for (let y = 0; y < n; y++) if (y !== i && paths[y][t] !== R) {
      const Ry = paths[y][t];
      if (P.nb[R].has(Ry)) out.push({ p: i, kind: 'heard', t, r: Ry, y, cons: [[y, t, Ry, false]] });
      out.push({ p: i, kind: 'absent', t, r: R, y, cons: [[i, t, R, false], [y, t, R, true]] });
    }
  }
  for (let t = 0; t < T - 1; t++) {
    let e = t; while (e + 1 < T && paths[i][e + 1] === paths[i][t]) e++;
    if (e > t && (t === 0 || paths[i][t - 1] !== paths[i][t])) { const c = []; for (let u = t; u <= e; u++) c.push([i, u, paths[i][t], false]); out.push({ p: i, kind: 'stayed', t, t2: e, r: paths[i][t], cons: c }); }
  }
  for (const R of P.roomIds) if (!paths[i].includes(R)) { const c = []; for (let t = 0; t < T; t++) c.push([i, t, R, true]); out.push({ p: i, kind: 'never', r: R, cons: c }); }
  return out;
}

// physical evidence (always true): photos and dark rooms
function factPool(paths, P) {
  const out = [];
  for (let t = 0; t < P.T; t++) for (const R of P.roomIds) {
    const here = []; for (let q = 0; q < P.n; q++) if (paths[q][t] === R) here.push(q);
    if (R === P.target) continue;
    if (here.length) { const c = []; for (let q = 0; q < P.n; q++) c.push([q, t, R, !here.includes(q)]); out.push({ p: -1, kind: 'photo', t, r: R, ys: here, cons: c }); }
    else { const c = []; for (let q = 0; q < P.n; q++) c.push([q, t, R, true]); out.push({ p: -1, kind: 'dark', t, r: R, cons: c }); }
  }
  return out;
}

function lieCandidates(th, paths, P) {
  const out = [], T = P.T, n = P.n;
  for (let t = 0; t < T; t++) for (const R of P.roomIds) if (R !== paths[th][t] && R !== P.target) {
    out.push({ p: th, kind: 'self', t, r: R, cons: [[th, t, R, false]], w: t === P.k ? 3 : 1 });
    for (let z = 0; z < n; z++) if (z !== th) out.push({ p: th, kind: 'saw', t, r: R, y: z, cons: [[th, t, R, false], [z, t, R, false]], w: t === P.k ? 2 : 0.6 });
    if (t < T - 1) { const c = [[th, t, R, false], [th, t + 1, R, false]]; out.push({ p: th, kind: 'stayed', t, t2: t + 1, r: R, cons: c, w: (t === P.k || t + 1 === P.k) ? 2 : 0.5 }); }
  }
  for (let y = 0; y < n; y++) if (y !== th && paths[y][P.k] !== P.target) out.push({ p: th, kind: 'heard', t: P.k, r: P.target, y, cons: [[y, P.k, P.target, false]], w: 1.5 });
  { const c = []; for (let t = 0; t < T; t++) c.push([th, t, P.target, true]); out.push({ p: th, kind: 'never', r: P.target, cons: c, w: 1.5 }); }
  return out.filter(s => !trueOf(s, paths));
}

const KIND_W = {
  easy: { self: 3, saw: 3, alone: 2, only: 1, heard: 1, absent: 1, stayed: 1, never: 0.5 },
  medium: { self: 2, saw: 2, alone: 2, only: 1.5, heard: 2, absent: 1.5, stayed: 1.5, never: 1 },
  hard: { self: 1, saw: 1.5, alone: 2, only: 2, heard: 2.5, absent: 2, stayed: 2, never: 1.5 },
};
function wpick(r, arr, wf) { let tot = 0; for (const a of arr) tot += wf(a); let x = r() * tot; for (const a of arr) { x -= wf(a); if (x <= 0) return a; } return arr[arr.length - 1]; }

function randomPath(r, P, nb, fixT, fixR, avoidT, avoidR) {
  for (let tries = 0; tries < 80; tries++) {
    const path = new Array(P.T);
    if (fixT != null) {
      path[fixT] = fixR;
      for (let t = fixT + 1; t < P.T; t++) path[t] = r() < 0.3 ? path[t - 1] : pick(r, [...nb[path[t - 1]]]);
      for (let t = fixT - 1; t >= 0; t--) path[t] = r() < 0.3 ? path[t + 1] : pick(r, [...nb[path[t + 1]]]);
    } else {
      path[0] = pick(r, P.roomIds);
      for (let t = 1; t < P.T; t++) path[t] = r() < 0.35 ? path[t - 1] : pick(r, [...nb[path[t - 1]]]);
    }
    if (avoidT != null && path[avoidT] === avoidR) continue;
    if (new Set(path).size < Math.min(3, P.T - 1)) continue;
    return path;
  }
  return null;
}

function tryGen(cfg, r) {
  const house = HOUSES[cfg.house], nb = neighbours(house);
  const P = { n: cfg.n, T: cfg.T, k: cfg.k, target: cfg.target, roomIds: house.rooms.map(x => x.id), nb };
  const W = KIND_W[cfg.diff];
  const th = Math.floor(r() * P.n);
  const paths = [];
  for (let i = 0; i < P.n; i++) {
    const p = i === th ? randomPath(r, P, nb, P.k, P.target) : randomPath(r, P, nb, null, null, P.k, P.target);
    if (!p) return null; paths.push(p);
  }
  // a locked door (medium/hard): a door nobody's true path uses at that moment
  const locks = [];
  const nLocks = { easy: 0, medium: r() < 0.5 ? 1 : 0, hard: 1 }[cfg.diff];
  for (let a = 0; a < 30 && locks.length < nLocks; a++) {
    const [da, db] = pick(r, HOUSES[cfg.house].doors), t = Math.floor(r() * (P.T - 1));
    if (paths.some(p => (p[t] === da && p[t + 1] === db) || (p[t] === db && p[t + 1] === da))) continue;
    if (Math.abs(t - P.k) > 1 && r() < 0.6) continue;
    locks.push([da, db, t]);
  }
  P.locks = locks; P.lockSet = lockSetOf(locks);
  // the thief must look ordinary: not in the target room the whole night
  if (paths[th].filter(x => x === P.target).length > 2) return null;
  const pools = paths.map((_, i) => truthPool(i, paths, P));
  const facts = factPool(paths, P);
  const nFacts = { easy: 1, medium: 2, hard: 2 }[cfg.diff];
  // the lie, with at least one innocent statement that cannot stand beside it
  let lies = lieCandidates(th, paths, P), chosen = null;
  while (lies.length && !chosen) {
    const l = wpick(r, lies, x => x.w * (cfg.diff === 'hard' && x.kind !== 'self' ? 2 : 1));
    const contra = []; for (let i = 0; i < P.n; i++) if (i !== th) for (const s of pools[i]) if (pairUnsat(l, s, P)) contra.push(s);
    for (const f of facts) if (pairUnsat(l, f, P) && r() < 0.35) contra.push(f);
    if (contra.length) chosen = { l, contra }; else lies = lies.filter(x => x !== l);
  }
  if (!chosen) return null;
  const lie = chosen.l;
  const S = [lie];
  const contra = pick(r, chosen.contra); S.push(contra);
  const count = i => S.filter(s => s.p === i).length;
  const has = s => S.includes(s);
  if (r() < 0.6) {
    const ok = pools[th].filter(s => s.t !== P.k && s.r !== P.target && s.kind !== 'never' && s.kind !== 'stayed' && !pairUnsat(s, lie, P));
    if (ok.length) S.push(wpick(r, ok, s => W[s.kind]));
  }
  for (let i = 0; i < P.n; i++) if (i !== th && !count(i)) S.push(wpick(r, pools[i], s => W[s.kind]));
  const nf = () => S.filter(s => s.p === -1).length;
  const maxPer = 3;
  for (let guard = 0; guard < 40; guard++) {
    const alts = suspects(S, P).filter(x => x !== th);
    if (!alts.length) break;
    const X = pick(r, alts);
    const opts = [];
    for (let i = 0; i < P.n; i++) if (i !== X && i !== th && count(i) < maxPer) for (const s of pools[i]) if (!has(s) && !candidateOK(X, S.concat([s]), P)) opts.push(s);
    if (nf() < nFacts) for (const f of facts) if (!has(f) && !candidateOK(X, S.concat([f]), P)) { f.w2 = 4; opts.push(f); }
    if (!opts.length) return null;
    S.push(wpick(r, opts, s => s.p === -1 ? 3 : W[s.kind] / (1 + count(s.p))));
  }
  if (suspects(S, P).join() !== String(th)) return null;
  // prune to taste
  const pruneShare = { easy: 0.2, medium: 0.6, hard: 1 }[cfg.diff];
  for (const s of shuffle(r, S)) {
    if (s === lie || r() > pruneShare) continue;
    const S2 = S.filter(x => x !== s);
    if (s.p >= 0 && S2.filter(x => x.p === s.p).length < 1) continue;
    if (!S2.some(x => x.p !== th && pairUnsat(lie, x, P))) continue;
    if (suspects(S2, P).join() !== String(th)) continue;
    S.splice(S.indexOf(s), 1);
  }
  // pad with harmless true statements (not about the thief, not touching the lie) so each person has a voice
  const want = { easy: 2, medium: 2, hard: 1 }[cfg.diff];
  const wantTotal = P.n + { easy: 3, medium: 3, hard: 2 }[cfg.diff];
  for (let i of shuffle(r, [...Array(P.n).keys()])) {
    while (count(i) < want || (S.length < wantTotal && count(i) < 2)) {
      const opts = pools[i].filter(s => !has(s) && !s.cons.some(c => c[0] === th) && !pairUnsat(lie, s, P) && (i !== th || (s.t !== P.k && s.r !== P.target)));
      if (!opts.length) break;
      const s = wpick(r, opts, s => W[s.kind]);
      S.push(s);
      if (S.length >= wantTotal && count(i) >= want) break;
    }
  }
  for (const f of shuffle(r, facts)) { if (nf() >= nFacts) break; if (!has(f) && !f.cons.some(c => c[0] === th && !c[3]) && !pairUnsat(lie, f, P)) S.push(f); }
  if (suspects(S, P).join() !== String(th)) return null;
  for (let i = 0; i < P.n; i++) if (count(i) < 1 || count(i) > maxPer) return null;
  if (!S.some(x => x.p >= 0 && x.p !== th && pairUnsat(lie, x, P))) return null;
  if (cfg.diff === 'hard' && S.filter(x => x.p !== th && pairUnsat(lie, x, P)).length > 1) return null;
  if (cfg.diff !== 'easy' && contraWhoAlsoTrivial(S, lie, th, P)) return null;
  // hard: the lie must need a second step that uses the evidence or the lock
  if (cfg.diff === 'hard') {
    const noFacts = S.filter(x => x.p !== -1);
    if (suspects(noFacts, P).join() === String(th) && !locks.length) return null;
  }
  S.sort((a, b) => a.p - b.p || (a.t ?? -1) - (b.t ?? -1));
  S.forEach((s, i) => { s.id = 's' + i; delete s.w; delete s.w2; });
  return { cfg, house: cfg.house, n: P.n, T: P.T, k: P.k, target: P.target, thief: th, paths, S, lie: lie.id, locks };
}
// for medium/hard: the person who contradicts the lie must not be cleared by nothing at all
// (i.e. removing every other statement, he would still be a suspect) -> puzzle needs a second step
function contraWhoAlsoTrivial(S, lie, th, P) {
  const cs = S.filter(x => x.p !== th && pairUnsat(lie, x, P));
  // trivial if with only the lie + contradictors, the thief is already unique
  return suspects([lie, ...cs], P).join() === String(th);
}

function generate(cfg, seed) {
  for (let a = 0; a < 3000; a++) { const g = tryGen(cfg, rng(seed * 7919 + a * 104729 + 17)); if (g) { g.seed = seed; g.attempt = a; return g; } }
  return null;
}
function ctx(g) { const house = HOUSES[g.house]; return { n: g.n, T: g.T, k: g.k, target: g.target, roomIds: house.rooms.map(x => x.id), nb: neighbours(house), locks: g.locks || [], lockSet: lockSetOf(g.locks || []) }; }

if (typeof module !== 'undefined') module.exports = { lockSetOf, HOUSES, generate, ctx, pairUnsat, suspects, trueOf, neighbours, feasible };
