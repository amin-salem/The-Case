"""Small authoring kit for case files.

Cases are written as compact Python (see cases_src/), and `python tools/build_cases.py`
turns them into the JSON files the server loads from app/content/cases/.
Avatars are generated from a seed, so every suspect looks different but stays the same on rebuild.
"""
from __future__ import annotations

import random
from datetime import date, timedelta

FIRST_NEW = 7
FIRST_PUBLISH = date(2026, 10, 5)  # c007; one new case every night after that

_OUTFITS = ["#1a237e", "#3e4a3e", "#4e342e", "#212121", "#37474f", "#5d4037", "#263238", "#6a1b1b",
            "#2c3e50", "#33463a", "#4a3b5c", "#7a5c2e", "#1b3a4b", "#5a2a3a", "#2e4a4a", "#444b57"]
_HAIR = ["#1a1a1a", "#2a2a2a", "#3e2723", "#424242", "#5d4037", "#6d1b1b", "#757575", "#263238"]


def S(name, role, age, gender, motive, statement, qa, acc=None, **look):
    """A suspect. qa = [(question, answer), ...]. look overrides avatar fields."""
    return dict(name=name, role=role, age=age, gender=gender, motive=motive, statement=statement,
                questions=[{"q": q, "a": a} for q, a in qa], acc=acc, look=look)


def E(type_, title, text):
    return dict(type=type_, title=title, text=text)


def _avatar(rng: random.Random, s: dict) -> dict:
    g, age = s["gender"], s["age"]
    grp = "young" if age < 30 else "mid" if age < 55 else "old"
    if g == "f":
        hair = rng.choice(["hijab", "hijab", "long", "short", "curly"])
        beard, acc = "none", s["acc"] or ("scarf" if hair == "hijab" else "none")
    else:
        hair = rng.choice(["short", "short", "slick", "curly", "cap"] + (["bald"] if grp != "young" else []))
        beard = rng.choice(["none", "none", "stubble", "mustache", "full"]) if grp != "young" else rng.choice(["none", "none", "stubble"])
        acc = s["acc"] or "none"
    color = "#bdbdbd" if grp == "old" and rng.random() < .7 else rng.choice(_HAIR)
    av = {"gender": g, "age": grp, "skin": rng.choice([0, 1, 1, 1, 2, 2, 3]), "hair": hair, "hairColor": color,
          "beard": beard, "glasses": rng.random() < .3, "outfit": rng.choice(_OUTFITS), "accessory": acc}
    av.update(s["look"])
    return av


def case(n, scene, difficulty, title, location, intro, suspects, evidence, hints, culprit, proof, explanation):
    """culprit and proof use numbers: culprit=3 means s3, proof=[2, 5] means e2 or e5 proves it."""
    rng = random.Random(n * 7919)
    sus = []
    for i, s in enumerate(suspects, 1):
        sus.append({"id": f"s{i}", "name": s["name"], "role": s["role"], "age": s["age"],
                    "avatar": _avatar(rng, s), "motive": s["motive"], "statement": s["statement"],
                    "questions": s["questions"]})
    ev = [{"id": f"e{i}", **e} for i, e in enumerate(evidence, 1)]
    return {
        "id": f"c{n:03d}", "number": n,
        "publish": (FIRST_PUBLISH + timedelta(days=n - FIRST_NEW)).isoformat(),
        "difficulty": difficulty, "scene": scene, "title": title, "location": location, "intro": intro,
        "suspects": sus, "evidence": ev, "hints": hints,
        "solution": {"culprit": f"s{culprit}", "proof": [f"e{p}" for p in proof], "explanation": explanation},
    }
