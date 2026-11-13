# Compares the hashes of an oracle with those of veslint's dump: counts per group of the corpus and the
# list of mismatches.
#   compare.py <oracle.tsv> <veslint.tsv> <corpus dir> <mismatches out>
import sys, os
oracle = {}
for line in open(sys.argv[1]):
    f, st, h = line.rstrip('\n').split('\t')
    oracle[f] = (st, h)
mine = {}
for line in open(sys.argv[2]):
    parts = line.rstrip('\n').split('\t')
    if len(parts) == 3:
        mine[parts[0]] = (parts[1], parts[2])
groups = {}
corpus = sys.argv[3]
for g in ['rules', 'upstream', 'scope', 'eval']:
    for f in open(os.path.join(corpus, g + '.txt')).read().split():
        groups[f] = g
stats = {}
mismatch = []
for f, (st, h) in oracle.items():
    g = groups.get(f, '?')
    s = stats.setdefault(g, {'inputs': 0, 'esterror': 0, 'tserror': 0, 'both': 0, 'missing': 0, 'match': 0, 'mismatch': 0})
    s['inputs'] += 1
    m = mine.get(f)
    if m is None:
        s['missing'] += 1
        mismatch.append(f + '\tmissing')
        continue
    if st != 'ok' and m[0] != 'ok':
        s['both'] += 1
    elif st != 'ok':
        s['esterror'] += 1
    elif m[0] != 'ok':
        s['tserror'] += 1
    elif m[1] == h:
        s['match'] += 1
    else:
        s['mismatch'] += 1
        mismatch.append(f)
tot = {}
for g, s in stats.items():
    print(g, s)
    for k, v in s.items():
        tot[k] = tot.get(k, 0) + v
print('total', tot)
compared = tot['match'] + tot['mismatch']
print(f"match rate: {tot['match']}/{compared} = {100.0 * tot['match'] / max(1, compared):.2f}%")
open(sys.argv[4], 'w').write('\n'.join(mismatch) + '\n')
