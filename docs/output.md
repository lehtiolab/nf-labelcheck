# lehtiolab/nf-labelcheck: Output

## Output
The output is a single file, qc.html, which summarises the result of the labelcheck run. See an example [here](example_qc.html)

## Pipeline overview
The pipeline is built using [Nextflow](https://www.nextflow.io/)
and processes data using the following steps:

* [MSGF+](#msgf) - Peptide identification search engine
* [Percolator](#percolator) - Target-decoy scoring
* [OpenMS](#openms) - Quantification of isobaric tags
* [Msstitch](#msstitch) - Post processing, protein inference

## MSGF+
[MSGF+](https://omics.pnl.gov/software/ms-gf) (aka MSGF+ or MSGFPlus) performs peptide identification by scoring MS/MS spectra against peptides derived from a protein sequence database.


## Percolator
[Percolator](http://percolator.ms/) is a semi-supervised machine learning program to better separate target vs decoy peptide scoring.


## OpenMS
[OpenMS](http://www.openms.de/) is a library that contains a large amount of tools for MS data analysis. This workflow uses its isobaric quantification program to extract peak intenstities for isobaric multiplex samples.


## Msstitch
[Msstitch](https://github.com/glormph/msstitch) is a package to merge identification and quantification PSM data, reporting PSM, peptide, protein and gene tables, adding q-values, quantitfications, protein groups, etc.
