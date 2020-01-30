#!/usr/bin/env python3

import sys
import re
from statistics import mean
import json

fn = sys.argv[1]
pepfield = sys.argv[2]
mod = sys.argv[3]
ml = len(mod)


def get_col_means(fn):
    with open(fn) as fp:
        head = next(fp).strip('\n').split('\t')
        plexcol = [x for x in filter(lambda y: 'plex' in y[1], [field for field in enumerate(head)])] 
        data = {x[1]: [] for x in plexcol} 
        for line in fp:
            line = line.strip('\n').split('\t')
            for col in plexcol:
                try:
                    data[col[1]].append(float(line[col[0]]))
                except ValueError:
                    pass  # caused by NA
    for col in plexcol:
        data[re.sub('[a-z0-9]+plex_', '', col[1])] = mean(data.pop(col[1]))
    with open('means', 'w') as fp:
        json.dump(data, fp)


def main():
    mccol = False
    outres = {'fails': 0, 'pass': 0, 'ntermfails': 0}
    if pepfield == 'Peptide': # PSM table passed
        get_col_means(fn)
    with open(fn) as fp:
        head = next(fp).strip('\n').split('\t')
        if pepfield == 'Peptide': # PSM table passed
            mccol = head.index('missed_cleavage')
            outres['missed'] = {}
        pepcol = head.index(pepfield)
        for line in fp:
            line = line.strip('\n').split('\t')
            pep = line[pepcol]
            if pep[:ml] != mod:
                outres['ntermfails'] += 1
                outres['fails'] +=1
            # TODO this treats nterm and other fails as identical
            else:
                outres['pass'] += 1
                for lys in re.finditer('K', pep):
                    ix = lys.start() + 1
                    if not pep[ix: ix+ml] == mod:
                        outres['fails'] += 1
                        outres['pass'] -= 1
                        break
            if mccol:
                try:
                    outres['missed'][line[mccol]] += 1
                except KeyError:
                    outres['missed'][line[mccol]] = 1
    with open('{}_stats.json'.format(fn), 'w') as fp:
        json.dump(outres, fp)


if __name__ == '__main__':
    main()
