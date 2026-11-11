"""Shared editorial rules; filenames never grant age or occupation permission."""
import re
from datetime import date


def pending_remap_deadline(row, release):
    """Finite review window; never an asset release date or usage permission.

    A confirmed/declared earlier usable_from ends the window immediately.
    Unknown release dates do not extend the 14-day maximum review period.
    """
    reviewed = date.fromisoformat(row['reviewed_on'])
    deadline = date.fromisoformat(row['waiting_until'])
    if not 0 < (deadline - reviewed).days <= 14:
        raise ValueError('pending review must expire within 14 days')
    dates = [deadline]
    for value in (row.get('allowed_from'), release.get('usable_from')):
        if value and value != '9999-12-31':
            dates.append(date.fromisoformat(value))
    return min(dates)

WOMEN_HEAD_COVERINGS = frozenset({'scarf', 'scarf_hair_visible'})


def head_covering_errors(asset):
    """Metadata contract; visual review must still check the actual image.

    No legacy bypass: a preserved noncompliant image is reported as a failure
    until its owner authorises a replacement. Never relabel bare hair as a scarf.
    """
    if asset.get('apparent_gender') == 'f' and asset.get('head_covering') not in WOMEN_HEAD_COVERINGS:
        return [f"{asset.get('id', '<unknown>')}: female head_covering must be scarf or scarf_hair_visible; got {asset.get('head_covering')!r}"]
    return []


def age_band(age):
    if age < 18:
        raise ValueError('Adult portrait age must be at least 18')
    return 'young' if age <= 30 else 'mid' if age <= 55 else 'old'


def normalise(text):
    text=re.sub('[\u064b-\u065f]', '', text)
    return re.sub(r'\s+', ' ', text.replace('ي', 'ی').replace('ك', 'ک').replace('\u200c', ' ')).strip()


def contains_term(text,term):
    term=normalise(term)
    # These ledger entries are deliberate phrase stems (ساختمان / ساختمانی).
    suffix='' if term in {'کارگر ساختم','کارگاه ساختم','پژوهشگر آزمایش'} else r'(?!\w)'
    return bool(re.search(r'(?<!\w)'+re.escape(term)+suffix,text))


def role_allowed(portrait, suspect):
    # role and intro describe THIS character. A witness statement may describe
    # someone else's occupation or finances, so it is not searched blindly.
    text = normalise(suspect['role'] + ' ' + suspect.get('intro', ''))
    forbidden = portrait['roles_not_ok']
    if any(contains_term(text,term) for term in forbidden if term != '*'):
        return False
    allowed = portrait['roles_ok']
    return '*' in allowed or any(contains_term(text,term) for term in allowed)


def available(portrait_id, case, releases, original_id=None):
    record = releases['portraits'].get(portrait_id)
    if not record:
        return True  # pre-existing pool, per the repository's release ledger
    if record.get('first_build') is None or not record.get('usable_from'):
        return False
    if case['publish'] >= record['usable_from']:
        return True
    # Historical grandfathering permits retention, never a new assignment.
    return (case['publish'] < releases['check_from'] and portrait_id == original_id)


def incompatibilities(portrait, suspect):
    errors = head_covering_errors(portrait)
    if portrait['apparent_gender'] != suspect['avatar']['gender']:
        errors.append('gender')
    if abs(portrait['apparent_age'] - suspect['age']) > 7:
        errors.append('age')
    if not role_allowed(portrait, suspect):
        errors.append('role/clothing')
    return errors


def can_assign(portrait, suspect, original_id=None):
    return (not incompatibilities(portrait, suspect) and
            (portrait.get('new_assignments_ok', True) or portrait['id'] == original_id))
