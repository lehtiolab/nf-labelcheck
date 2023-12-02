# lehtiolab/nf-labelcheck

**A proteomics pipeline for running labelchecks**.

[![Build Status](https://api.travis-ci.org/lehtiolab/nf-labelcheck.svg?branch=master)](https://travis-ci.org/lehtiolab/nf-labelcheck)
[![Nextflow](https://img.shields.io/badge/nextflow-%E2%89%A519.04.1-brightgreen.svg)](https://www.nextflow.io/)

[![install with bioconda](https://img.shields.io/badge/install%20with-bioconda-brightgreen.svg)](http://bioconda.github.io/)
[![Docker](https://img.shields.io/badge/docker%20build-automated-blue)](https://hub.docker.com/r/lehtiolab/nf-labelcheck)

## Introduction
The pipeline is built using [Nextflow](https://www.nextflow.io), a workflow tool to run tasks across multiple compute infrastructures in a very portable manner. It comes with docker containers making installation trivial and results highly reproducible.

## How to run

- install [Nextflow](https://nextflow.io)
- install [Docker](https://docs.docker.com/engine/installation/), [Singularity](https://www.sylabs.io/guides/3.0/user-guide/), or [Conda](https://conda.io/miniconda.html)
- run pipeline:

```nextflow run lehtiolab/nf-labelcheck --input '/path/to/inputdef.txt' --tdb /path/to/proteins.fa --isobaric tmt10plex```

Where `inputdef.txt` is a tab-separated file containing a header for one-channel-per-file runs:

```
mzmlfile    instrument    setname    channel
/path/to/fn.mzML    qe    setA    126
...
```

or pooled channels in a file:
```
mzmlfile    instrument    setname
/path/to/fn.mzML    qe    setA
...
```

Each of these inputs leads to a slightly different report, see examples for [pooled](docs/pooled_qc.html), and [non-pooled](docs/nonpooled_qc.html) results.
The pipeline performs identification and quantification, and the output contains graphs to display the amount of incorporated isobaric label per sample on both peptide and PSM level.
For the non-pooled runs, a PSM/peptide is considered to be not labeled if any of its K residues or its N-term have not been labeled. For pooled reports there is information
on the amount of PSMs with missing values per channel. The report also shows the amount of labeling in the different channels per sample,
as well as missed cleavages.

The lehtiolab/nf-labelcheck pipeline comes with documentation about the pipeline, found in the `docs/` directory:

- [Running the pipeline](docs/usage.md)
- [Output and how to interpret the results](docs/output.md)
- [Troubleshooting](https://nf-co.re/usage/troubleshooting)

## Credits
lehtiolab/nf-labelcheck was originally written by Jorrit Boekel and tries to follow the [nf-core](https://nf-co.re) best practices and templates.
