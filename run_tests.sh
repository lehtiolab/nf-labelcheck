#!/usr/bin/env bash

red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)


export NXF_VER=22.10.5

rundir=$(pwd)
export repodir=$(dirname "$(realpath -s "$0")")
export testdir="${repodir}/tests/"
export testdata="${rundir}/static-resources/test-data/nf-labelcheck"

if [ -e "${testdata}" ]
then
    cd "${testdata}" && git checkout labelcheck_test_data && cd "${rundir}"
else
    git clone --single-branch --branch labelcheck_test_data https://github.com/lehtiolab/static-resources
fi

[ -e test_output ] && rm -r test_output

declare -A results

test_names=(
    pooled
)

echo ${testdata}
for testname in ${test_names[@]}
do
    bash "${testdir}/${testname}.sh"
    results["$testname"]="$?"
done

for testname in ${test_names[@]}
do
    if [[ ${results["$testname"]} == 0 ]]
    then
        echo ${green}"$testname" - SUCCESS ${reset}
    else
        echo ${red}"$testname" - FAIL ${reset}
    fi
done
