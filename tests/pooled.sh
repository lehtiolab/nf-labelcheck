#!/usr/bin/env bash

set -eu

echo Pooled test
name=pooled
nextflow run -resume -profile test ${repodir}/main.nf --name ${name} \
    --outdir test_output/${name} \
    --input  <(cat "${testdir}/pooled_mzml.txt" | envsubst) \
    --tdb "${testdata}/small_sp.fasta" \
    --isobaric tmt10plex

echo Non pooled test
name=nonpooled
nextflow run -resume -profile test ${repodir}/main.nf --name ${name} \
    --outdir test_output/${name} \
    --input  <(cat "${testdir}/non_pooled_mzml.txt" | envsubst) \
    --tdb "${testdata}/small_sp.fasta" \
    --isobaric tmt10plex
