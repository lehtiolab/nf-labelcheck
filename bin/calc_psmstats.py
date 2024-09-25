#!/usr/bin/env python3

import sys
import re
from collections import defaultdict
from statistics import median
import json


def get_col_medians(fn, maxmis, mod):
    if mod:
        ml = len(mod)
    with open(fn) as fp:
        head = next(fp).strip('\n').split('\t')
        mccol = head.index('missed_cleavage')
        try:
            pepcol = head.index('Peptide')
        except ValueError:
            pepcol = head.index('Peptide sequence')

        # Isobaric intensities
        plexcols = [x for x in filter(lambda y: 'plex' in y[1], [field for field in enumerate(head)])] 
        data = {'medians': defaultdict(list), 'missingvals': {x[1]: 0 for x in plexcols}}
        miscleav = {x: 0 for x in range(0, maxmis + 1)}
        numpsms, passing, ntermfails, fails = 0, 0, 0, 0
        for line in fp:
            line = line.strip('\n').split('\t')
            numpsms += 1
            pep = line[pepcol]
            # There is always a mod in labelcheck, but maybe not in dig checks
            if mod and pep[:ml] != mod:
                ntermfails += 1
                fails +=1
            # TODO this treats nterm and other fails as identical
            elif mod:
                passing += 1
                for lys in re.finditer('K', pep):
                    ix = lys.start() + 1
                    if not pep[ix: ix+ml] == mod:
                        fails += 1
                        passing -= 1
                        break
            #is_missed = False
            num_mis = int(line[mccol])
            if num_mis <= maxmis:
               # is_missed = True
                miscleav[int(line[mccol])] += 1
            for col in plexcols:
                val = line[col[0]]
                try:
                    intensity = float(val)
                except ValueError:
                    data['missingvals'][col[1]] += 1
               #     if is_missed:
               #         data[col[1]]['miscleav_int'][num_mis].append(0)
                else:
                    if intensity == 0:
                        data['missingvals'][col[1]] += 1
                    else:
                        data['medians'][col[1]].append(intensity)
               #     if is_missed:
               #         data[col[1]]['miscleav_int'][num_mis].append(intensity)
    for col in plexcols:
        # Remove keys "tmt10plex_128C" etc, replace with "128C"
        ch = re.sub('[a-z0-9]+plex_', '', col[1])
        try:
            intensities = data['medians'].pop(col[1])
        except KeyError:
            intensities = [0]
        try:
            medianints = median(intensities)
        except ValueError:
            # E.g. empty channel, should not happen though as we already have KeyError above
            medianints = 0
        data['medians'][ch] = medianints 
        # Also for missing values:
        misvals = data['missingvals'].pop(col[1])
        data['missingvals'][ch] = float(misvals) / numpsms * 100

#        for mcn, ints in vals['miscleav_int'].items():
#            try:
#                medint = median(ints)
#            except ValueError:
#                medint = 0
#            data[ch]['miscleav'][mcn] = medint / medianints
    data['miscleav'] = {num: amount / numpsms * 100 for num, amount in miscleav.items()}
    data.update({'pass': passing, 'fail': fails})
    return data

'''If non-pooled, call this:

calc_psmstats.py psmfn.txt pepfn.txt MZMLFN.mzML maxmiscl

Use the mzML file as an identifier
'''

def main():
    psmfn = sys.argv[1]
    pepfn = sys.argv[2]
    identifier = sys.argv[3] # setname or mzml file name
    maxmis = int(sys.argv[4])
    mod = sys.argv[5] if len(sys.argv) > 5 else False
    channels = []#sys.argv[5].split(',') if len(sys.argv) > 5 else []
    samples = [] # sys.argv[6].split(',') if len(sys.argv) > 6 else []

    if len(channels) == 0:
        with open(psmfn) as fp:
            head = next(fp).strip('\n').split('\t')
            channels = [re.sub('[a-z0-9]+plex_', '', x) for x in head if 'plex' in x]

    outres = {'filename': identifier, 'samples': samples, 'channels': channels,
            'psms': get_col_medians(psmfn, maxmis, mod), 'peps': get_col_medians(pepfn, maxmis, mod)}
    with open(psmfn) as fp:
        head = next(fp).strip('\n').split('\t')
    with open(f'{identifier}_stats.json', 'w') as fp:
        json.dump(outres, fp)


if __name__ == '__main__':
    main()
