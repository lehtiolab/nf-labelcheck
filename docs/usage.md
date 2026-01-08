# lehtiolab/nf-labelcheck: Usage

## Table of contents
* [Table of contents](#table-of-contents)
* [Introduction](#introduction)
* [Running the pipeline](#running-the-pipeline)
  * [Updating the pipeline](#updating-the-pipeline)
  * [Reproducibility](#reproducibility)
* [Main arguments](#main-arguments)
* [Job resources](#job-resources)
  * [Automatic resubmission](#automatic-resubmission)
* [Other command line parameters](#other-command-line-parameters)


## Introduction
Nextflow handles job submissions on SLURM or other environments, and supervises running the jobs. Thus the Nextflow process must run until the pipeline is finished. We recommend that you put the process running in the background through `screen` / `tmux` or similar tool. Alternatively you can run nextflow within a cluster job submitted your job scheduler.

It is recommended to limit the Nextflow Java virtual machines memory. We recommend adding the following line to your environment (typically in `~/.bashrc` or `~./bash_profile`):

```bash
NXF_OPTS='-Xms1g -Xmx4g'
```

<!-- TODO if this ever gets into nf-core, change the nf repo -->
## Running the pipeline
The typical command for running the pipeline is as follows:

```bash
nextflow run lehtiolab/nf-labelcheck --input 'mzmls.txt' --tdb swissprot_20181011.fa --isobaric tmt10plex -profile standard,docker
```

This will launch the pipeline with the `docker` configuration profile. See below for more information about profiles.

Note that the pipeline will create the following files in your working directory:

```bash
work            # Directory containing the nextflow working files
results         # Finished results (configurable, see below)
.nextflow_log   # Log file from Nextflow
# Other nextflow hidden files, eg. history of pipeline runs and old logs.
```

### Updating the pipeline
When you run the above command, Nextflow automatically pulls the pipeline code from GitHub and stores it as a cached version. When running the pipeline after this, it will always use the cached version if available - even if the pipeline has been updated since. To make sure that you're running the latest version of the pipeline, make sure that you regularly update the cached version of the pipeline:

```bash
nextflow pull lehtiolab/nf-labelcheck
```

### Reproducibility
It's a good idea to specify a pipeline version when running the pipeline on your data. This ensures that a specific version of the pipeline code and software are used when you run your pipeline. If you keep using the same tag, you'll be running the same version of the pipeline, even if there have been changes to the code since.

First, go to the [lehtiolab/nf-labelcheck releases page](https://github.com/lehtiolab/nf-labelcheck/releases) and find the latest version number - numeric only (eg. `1.3.1`). Then specify this when running the pipeline with `-r` (one hyphen) - eg. `-r 1.3.1`.

This version number will be logged in reports when you run the pipeline, so that you'll know what you used when you look back in the future.


## Main arguments

### `-profile`
Use this parameter to choose a configuration profile. Profiles can give configuration presets for different compute environments. Note that multiple profiles can be loaded, for example: `-profile docker` - the order of arguments is important!

If `-profile` is not specified at all the pipeline will be run locally and expects all software to be installed and available on the `PATH`.

* `docker`
  * A generic configuration profile to be used with [Docker](http://docker.com/)
  * Pulls software from docker registries
* `singularity`
  * A generic configuration profile to be used with [Singularity](http://singularity.lbl.gov/)
  * Pulls software from docker registries or Galaxy's singularity depot
* `test`
  * A profile with a complete configuration for automated testing

### `--input`
Specify input spectra, pass a text file which contains the mzML specifications

```bash
--input /path/to/data/mzmls.txt
```

This text file is tab-separated without header, contains a single line per mzML file/channel combination, specified as follows:

```/path/to/file<TAB>instrument<TAB>setname```

Instrument is for the search engine and should be one of `[qe, velos, tof, lowres]`, e.g.:

```
/path/to/mzmls/20190715_TMT10_setA_LC.mzML   qe    setA
/path/to/mzmls/20190715_TMT10_setB_LC.mzML   velos    setB
```
This will work for both pooled and single-channel runs, but if you have the luxury to run single channel MS time,
you may want to use v1.2 of this pipeline which gives a nicer report, including more precise missed cleavage data.


### `--sampletable`
Tab separated file containing the sample names per channel for annotation in QC output, as follows:

```
126     setA    sample1
127N    setA    sample2
127C    setA    sample3
126     setA    sample4
127N    setA    sample5
127C    setA    sample6
```


### `--tdb`
Target database. Decoy databases are created "tryptic-reverse" by the pipeline and searches are against a
concatenated database (T-TDC).

```bash
--tdb /path/to/Homo_sapiens.pep.all.fa
```


### `--isobaric`
Isobaric multiplexing chemistry used, e.g. tmt10plex, itraq8plex, tmt18plex, etc

```bash
--isobaric tmt16plex
```

### `--activation`
The MS fragmentation activation method used, used by the IsobaricQuant program from OpenMS. Default is `hcd`, but `cid`, `etd` can also be used.

### `--maxmissedcleavages`
The maximum amount of allowed missed cleavages in the report and search. Default is 2.

### `--maxvarmods`
The maximum amount of variable modifications per peptide, default is 2.

### `--prectol`
Precursor tolerance, default is '10.0ppm'

### `--minpeplen, --maxpeplen, --mincharge, --maxcharge`
Minimum/maximum length and charge for peptides


## Job resources
### Automatic resubmission
Each step in the pipeline has a default set of requirements for number of CPUs, memory and time. For most of the steps in the pipeline, if the job exits with an error code of `143` (exceeded requested resources) it will automatically resubmit with higher requests (2 x original, then 3 x original). If it still fails after three times then the pipeline is stopped.


## Other command line parameters

### `--outdir`
The output directory where the results will be saved.

### `-name` or `--name`
Name for the pipeline run. If not specified, Nextflow will automatically generate a random mnemonic.

### `-resume`
Specify this when restarting a pipeline. Nextflow will used cached results from any pipeline steps where the inputs are the same, continuing from where it got to previously.

You can also supply a run name to resume a specific run: `-resume [run-name]`. Use the `nextflow log` command to show previous run names.

**NB:** Single hyphen (core Nextflow option)

### `-c`
Specify the path to a specific config file (this is a core NextFlow command).

**NB:** Single hyphen (core Nextflow option)

Note - you can use this to override pipeline defaults.

## Run the pipeline
cd /path/to/my/data
nextflow run /path/to/pipeline/ --custom_config_base /path/to/my/configs/configs-master/
