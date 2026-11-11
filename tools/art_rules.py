"""Shared editorial rules; filenames never grant age or occupation permission."""
import re


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
    if record.get('first_build') is None:
        return False
    if case['publish'] >= record['usable_from']:
        return True
    # Historical grandfathering permits retention, never a new assignment.
    return (case['publish'] < releases['check_from'] and portrait_id == original_id)


def incompatibilities(portrait, suspect):
    errors = []
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
