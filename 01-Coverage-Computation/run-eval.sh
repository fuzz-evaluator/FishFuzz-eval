#!/bin/bash
set -eu
set -o pipefail

DIR="$(dirname $(readlink -f $0))"
readonly ROOT_DIR="$(readlink -f "$DIR/..")"
source $ROOT_DIR/config.sh

FISH_FUZZ_ROOT=$ROOT_DIR/FishFuzz-upstream
FUZZ_OUT_DIR="$DIR/eval-results"

FUZZERS=('ffafl' 'ffapp' 'afl' 'aflpp')
TARGETS=('cflow' 'cxxfilt' 'w3m' 'mujs' 'mutool' 'tic' 'dwarfdump')

########## Configuration ##########

# Number of available CPUs.
# This determine the number of parallel fuzzing instances.
readonly CPUS=10

# LAST_TRIAL-FIRST_TRIAL determines the number of repetitions.
# Choosing disjoint intervals allows to run multiple evaluations in parallel.
readonly FIRST_TRIAL=1
readonly LAST_TRIAL=10

# Timeout of each individual fuzzing run.
readonly DURATION=24h

###################################

if ! command -v parallel > /dev/null || ! parallel --version | grep -q "GNU parallel"; then
    echo "Please install GNU parallel"
    exit 1
fi

if [[ -d "$FUZZ_OUT_DIR" ]]; then
    echo "$FUZZ_OUT_DIR exists, please delete and rerun"
    exit 1
fi
mkdir -p "$FUZZ_OUT_DIR"

args=""
core_idx=0
for trial in $(seq $FIRST_TRIAL $LAST_TRIAL); do
    for target in "${TARGETS[@]}"; do
        for fuzzer in "${FUZZERS[@]}"; do
            args+="$target@$fuzzer@$trial@$core_idx "
            core_idx=$(((core_idx+1) % CPUS))
        done
    done
done

echo -ne $args

function run_fuzzer () {
    set -eu
    set -o pipefail

    # Trim trailing whitespace from last element.
    local arg="$(echo -ne $1 | tr -d ' ')"

    # Args are seperated by the '@' character.
    target="$(echo -ne $arg | cut -d '@' -f 1)"
    fuzzer="$(echo -ne $arg | cut -d '@' -f 2)"
    trial="$(echo -nw $arg | cut -d '@' -f 3)"
    core="$(echo -nw $arg | cut -d '@' -f 4)"

    echo "fuzzer: $fuzzer"
    echo "target: $target"
    echo "trial: $trial"
    echo "core: $core"

    out_dir="${FUZZ_OUT_DIR}/${fuzzer}-${target}-$DURATION-${trial}"
    rm -rf "$out_dir"

    cp -a "$FISH_FUZZ_ROOT/paper/artifact/two-stage" "$out_dir"
    cd "$out_dir"

    # Generate the scripts for each fuzzer harness
    python3 scripts/generate_script.py -b "$PWD/runtime/fuzz_script" > /dev/null

    # Create the folder structure expected by the fuzzer/scripts
    python3 scripts/generate_runtime.py -b "$PWD/runtime" > /dev/null

    cmd="docker run -t -v "${out_dir}/runtime:/work" -e AFL_NO_UI=1 --name ${fuzzer}_${target}_${trial} --cpuset-cpus $core $TWO_STAGE_ARTIFACT_DOCKER_IMAGE_NAME timeout $DURATION "/work/fuzz_script/$fuzzer/${target}.sh""
    echo $cmd
    $cmd

}

# Export the `run_fuzzer` function such that it can be passed to `parallel`.
export -f run_fuzzer
# Export variables used in the `run_fuzzer` function.
export DURATION
export TWO_STAGE_ARTIFACT_DOCKER_IMAGE_NAME
export FUZZ_OUT_DIR
export WORK_DIR
export FISH_FUZZ_ROOT

# Start processing the tasks.
echo -ne $args | parallel -j $CPUS --bar -kd' ' -- run_fuzzer {} ';' || true
