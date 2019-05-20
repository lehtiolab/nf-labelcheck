#!/usr/bin/env python3

import sys
import re

pepfield = sys.argv[2]
mod = sys.argv[3]
ml = len(mod)

with open(sys.argv[1]) as fp:
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
sys.stderr.write('{} {}\n'.format(full_psms, fails))


