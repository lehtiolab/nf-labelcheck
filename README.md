# nf-core/labelcheck

**A proteomics pipeline for running labelchecks**.

[![Build Status](https://travis-ci.com/nf-core/labelcheck.svg?branch=master)](https://travis-ci.com/nf-core/labelcheck)
[![Nextflow](https://img.shields.io/badge/nextflow-%E2%89%A50.32.0-brightgreen.svg)](https://www.nextflow.io/)

[![install with bioconda](https://img.shields.io/badge/install%20with-bioconda-brightgreen.svg)](http://bioconda.github.io/)
[![Docker](https://img.shields.io/docker/automated/nfcore/labelcheck.svg)](https://hub.docker.com/r/glormph/nfcore-labelcheck)

## Introduction
The pipeline is built using [Nextflow](https://www.nextflow.io), a workflow tool to run tasks across multiple compute infrastructures in a very portable manner. It comes with docker containers making installation trivial and results highly reproducible.


## Documentation
The nf-core/labelcheck pipeline comes with documentation about the pipeline, found in the `docs/` directory:

1. [Installation](https://nf-co.re/usage/installation)
2. Pipeline configuration
    * [Local installation](https://nf-co.re/usage/local_installation)
    * [Adding your own system config](https://nf-co.re/usage/adding_own_config)
    * [Reference genomes](https://nf-co.re/usage/reference_genomes)
3. [Running the pipeline](docs/usage.md)
4. [Output and how to interpret the results](docs/output.md)
5. [Troubleshooting](https://nf-co.re/usage/troubleshooting)

The labelcheck pipeline takes multiple mzML files as input and performs identification and quantification to output an HTML report containing graphs to display the amount of incorporated isobaric label per sample on both peptide and PSM level. A PSM/peptide is considered to be not labeled if any of its K residues or its N-term have not been labeled. The report also shows the amount of labeling in the different channels per sample.

## Credits
nf-core/labelcheck was originally written by Jorrit Boekel.
