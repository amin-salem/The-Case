"""Players never see card ids («e5») in the explanation: they are replaced by the card titles (Amin, 23 Oct 2026)."""
import re

from app import content


def test_readable_replaces_every_id_with_the_card_title():
    for c in (*content.all_cases(), *content.weekly_cases()):
        texts = [c.data["solution"]["explanation"]]
        if isinstance(c.data.get("night1"), dict):
            texts.append(c.data["night1"]["explanation"])
        for t in texts:
            out = content.readable(t, c.data)
            assert not re.search(r"\be\d+\b", out), c.id
            assert re.search(r"\be\d+\b", t) is None or "«" in out, c.id


def test_readable_example():
    data = {"evidence": [{"id": "e1", "title": "فاکتور"}, {"id": "e2", "title": "گزارش"}]}
    assert content.readable("(e1, e2) و e9", data) == "(«فاکتور», «گزارش») و یکی از مدارک"
