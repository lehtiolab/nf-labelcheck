#!/usr/bin/env python3

import sys
import re
from statistics import median
import json


def get_col_medians(fn, maxmis):
    with open(fn) as fp:
        head = next(fp).strip('\n').split('\t')
        mccol = head.index('missed_cleavage')
        # Isobaric intensities
        plexcol = [x for x in filter(lambda y: 'plex' in y[1], [field for field in enumerate(head)])] 
        data = {x[1]: {'intensities': [], 'missingvals': 0} for x in plexcol} 
        miscleav = {x: 0 for x in range(0, maxmis + 1)}
        numpsms = 0
        for line in fp:
            line = line.strip('\n').split('\t')
            numpsms += 1
            is_missed = False
            num_mis = int(line[mccol])
            if num_mis <= maxmis:
               # is_missed = True
                miscleav[int(line[mccol])] += 1
            for col in plexcol:
                val = line[col[0]]
                try:
                    intensity = float(val)
                except ValueError:
                    data[col[1]]['missingvals'] += 1
               #     if is_missed:
               #         data[col[1]]['miscleav_int'][num_mis].append(0)
                else:
                    if intensity == 0:
                        data[col[1]]['missingvals'] += 1
                    else:
                        data[col[1]]['intensities'].append(intensity)
               #     if is_missed:
               #         data[col[1]]['miscleav_int'][num_mis].append(intensity)
    for col in plexcol:
        vals = data.pop(col[1])
        try:
            medianints = median(vals['intensities'])
        except ValueError:
            # E.g. empty channel
            medianints = 0
        ch = re.sub('[a-z0-9]+plex_', '', col[1])
        data[ch] = {'median': medianints, 'missingvals': float(vals['missingvals']) / numpsms * 100}
#        for mcn, ints in vals['miscleav_int'].items():
#            try:
#                medint = median(ints)
#            except ValueError:
#                medint = 0
#            data[ch]['miscleav'][mcn] = medint / medianints
    data['miscleav'] = {num: amount / numpsms * 100 for num, amount in miscleav.items()}
    return data


def main():
    psmfn = sys.argv[1]
    pepfn = sys.argv[2]
    setname = sys.argv[3]
    maxmis = int(sys.argv[4])
    channels = sys.argv[5].split(',') if len(sys.argv) > 5 else []
    samples = sys.argv[6].split(',') if len(sys.argv) > 6 else []

    if len(channels) == 0:
        with open(psmfn) as fp:
            head = next(fp).strip('\n').split('\t')
            channels = [re.sub('[a-z0-9]+plex_', '', x) for x in head if 'plex' in x]

    outres = {'filename': setname, 'samples': samples, 'channels': channels,
            'psms': get_col_medians(psmfn, maxmis), 'peps': get_col_medians(pepfn, maxmis)}
    with open(psmfn) as fp:
        head = next(fp).strip('\n').split('\t')
    with open('{}_stats.json'.format(setname), 'w') as fp:
        json.dump(outres, fp)


if __name__ == '__main__':
    main()
