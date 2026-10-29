import re, sys, unicodedata, collections
import os
REF = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'docs', 'dictation-spike-script.md')
ref = open(REF).read().split('## Reference')[1].split('## Counting')[0]
names = re.findall(r"\*\*(.+?)\*\*", ref)
expected = collections.Counter(names)
def fold(s):  # lenient: case and diacritics
    return ''.join(c for c in unicodedata.normalize('NFD', s) if unicodedata.category(c) != 'Mn').lower()
def clip(t):  # the read-aloud part only
    i = t.lower().find('end of the read')
    return t[:i] if i > 0 else t
def norm(x): return re.sub(r'[^0-9a-z]+',' ',fold(x).lower()).strip()
def count(t, name, lenient):
    return len(re.findall(r'(?<![0-9a-z])'+re.escape(norm(name))+r'(?![0-9a-z])', norm(t)))
def _old_count(t, name, lenient):
    f = (lambda x: x) if not lenient else fold
    t = re.sub(r"\s+", " ", t)
    n = 0
    for m in re.finditer(re.escape(f(name).lower() if lenient else name), f(t).lower() if lenient else t, flags=0 if lenient else re.I):
        n += 1
    return n
for label in sys.argv[1:]:
    t = clip(open(label).read())
    print(f"\n=== {label}  (read-aloud part: {len(t.split())} of ~365 script words)")
    tot = {False: 0, True: 0}
    rows = []
    for name, exp in expected.items():
        s = min(exp, count(t, name, False)); l = min(exp, count(t, name, True))
        tot[False] += s; tot[True] += l
        rows.append((name, exp, s, l))
    for name, exp, s, l in rows:
        if s < exp: print(f"  {name:22} expected {exp}, right {s}" + (f" (ignoring accents {l})" if l != s else ""))
    n = sum(expected.values())
    print(f"  TOTAL: {n} occurrences; exact {tot[False]} right, {n-tot[False]} mangled; ignoring accents {tot[True]} right, {n-tot[True]} mangled")
