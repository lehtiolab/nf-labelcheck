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
        data[col[1]] = mean(data[col[1]])
    with open('means', 'w') as fp:
        json.dump(data, fp)


def main():
    if pepfield == 'Peptide': # PSM table passed
        get_col_means(fn)
    with open(fn) as fp:
        head = next(fp).strip('\n').split('\t')
        pepcol = head.index(pepfield)
        fails, ntermfails, full_psms = 0, 0, 0
        for line in fp:
            line = line.strip('\n').split('\t')
            pep = line[pepcol]
            if pep[:ml] != mod:
                ntermfails += 1
                fails +=1
            # TODO this treats nterm and other fails as identical
            else:
                full_psms += 1
                for lys in re.finditer('K', pep):
                    ix = lys.start() + 1
                    if not pep[ix: ix+ml] == mod:
                        fails += 1
                        full_psms -= 1
                        break
    sys.stdout.write('{} {}'.format(full_psms, fails))


if __name__ == '__main__':
    main()
