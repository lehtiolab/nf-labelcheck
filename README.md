# lehtiolab/nf-labelcheck

**A proteomics pipeline for running labelchecks**.

[![Build Status](https://api.travis-ci.org/glormph/nf-core-labelcheck.svg?branch=master)](https://travis-ci.org/glormph/nf-core-labelcheck)
[![Nextflow](https://img.shields.io/badge/nextflow-%E2%89%A519.04.1-brightgreen.svg)](https://www.nextflow.io/)

[![install with bioconda](https://img.shields.io/badge/install%20with-bioconda-brightgreen.svg)](http://bioconda.github.io/)
[![Docker](https://img.shields.io/docker/automated/glormph/nfcore-labelcheck.svg)](https://hub.docker.com/r/glormph/nfcore-labelcheck)

## Introduction
The pipeline is built using [Nextflow](https://www.nextflow.io), a workflow tool to run tasks across multiple compute infrastructures in a very portable manner. It comes with docker containers making installation trivial and results highly reproducible.

## How to run

- install [Nextflow](https://nextflow.io)
- install [Docker](https://docs.docker.com/engine/installation/), [Singularity](https://www.sylabs.io/guides/3.0/user-guide/), or [Conda](https://conda.io/miniconda.html)
- run pipeline:

```nextflow run lehtiolab/nf-labelcheck --mzmls '/path/to/*.mzML' --tdb /path/to/proteins.fa```

The lehtiolab/nf-labelcheck pipeline comes with documentation about the pipeline, found in the `docs/` directory:

- [Running the pipeline](docs/usage.md)
- [Output and how to interpret the results](docs/output.md)
- [Troubleshooting](https://nf-co.re/usage/troubleshooting)

The labelcheck pipeline takes multiple mzML files as input and performs identification and quantification to output an HTML report ([an example can be found here](docs/example_qc.html)) containing graphs to display the amount of incorporated isobaric label per sample on both peptide and PSM level. A PSM/peptide is considered to be not labeled if any of its K residues or its N-term have not been labeled. The report also shows the amount of labeling in the different channels per sample.

## Credits
lehtiolab/nf-labelcheck was originally written by Jorrit Boekel and tries to follow the [nf-core](https://nf-co.re) best practices and templates.
