"""One startup-time root for every runtime content loader; never overlay private and bundled files."""
from pathlib import Path

from .config import get_settings


def content_root() -> Path:
    configured = get_settings().content_dir.strip()
    if not configured:
        return Path(__file__).parent / "content"
    root = Path(configured).expanduser().resolve()
    # An explicit external bundle must be complete. A typo must not fall back to public answers.
    if not root.is_dir() or any(not (root / name).is_dir() for name in ("cases", "weekly", "story")):
        raise ValueError("CONTENT_DIR must contain cases/, weekly/ and story/ directories")
    if not (root / "riddles.json").is_file():
        raise ValueError("CONTENT_DIR must contain riddles.json")
    return root


CONTENT_ROOT = content_root()
