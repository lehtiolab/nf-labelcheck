#!/usr/bin/env python
from __future__ import print_function
from collections import OrderedDict
import re

regexes = {
    'lehtiolab/nf-labelcheck': ['v_pipeline.txt', r"(\S+)"],
    'Nextflow': ['v_nextflow.txt', r"(\S+)"],
    'MSGF+': ['v_msgf.txt', r"([0-9\.]+)"],
    'Percolator': ['v_perco.txt', r"([0-9\.]+)"],
    'msstitch': ['v_mss.txt', r"(\S+)"],
    'OpenMS': ['v_openms.txt', r"Version: ([0-9A-Z\-\.]+)"],
}
results = OrderedDict()
results['lehtiolab/nf-labelcheck'] = '<span style="color:#999999;\">N/A</span>'
results['Nextflow'] = '<span style="color:#999999;\">N/A</span>'

# Search each file using its regex
for k, v in regexes.items():
    with open(v[0]) as x:
        versions = x.read()
        match = re.search(v[1], versions)
        if match:
            results[k] = "v{}".format(match.group(1))

# Remove software set to false in results
for k in results:
    if not results[k]:
        del(results[k])

# Dump to YAML
print ('''
id: 'software_versions'
section_name: 'lehtiolab/nf-labelcheck Software Versions'
section_href: 'https://github.com/lehtiolab/nf-labelcheck'
plot_type: 'html'
description: 'are collected at run time from the software output.'
data: |
    <dl class="dl-horizontal">
''')
for k,v in results.items():
    print("        <dt>{}</dt><dd><samp>{}</samp></dd>".format(k,v))
print ("    </dl>")

# Write out regexes as csv file:
with open('software_versions.csv', 'w') as f:
    for k,v in results.items():
        f.write("{}\t{}\n".format(k,v))
