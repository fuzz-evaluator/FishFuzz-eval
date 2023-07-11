#!/bin/bash
set -eu
set -o pipefail

DIR="$(dirname $(readlink -f $0))"
readonly ROOT_DIR="$(readlink -f "$DIR/..")"
source $ROOT_DIR/config.sh

readonly FISH_FUZZ_ROOT=$ROOT_DIR/FishFuzz-upstream

readonly CPUS=40

if [[ $# -ne 1 ]]; then
    echo "Please use $0 <path-to-eval-results-dir>"
    exit 1
fi

if ! command -v parallel > /dev/null || ! parallel --version | grep -q "GNU parallel"; then
    echo "Please install GNU parallel"
    exit 1
fi

readonly EVAL_RESULT_DIR="$1"

if [[ ! -d "$EVAL_RESULT_DIR" ]]; then
    echo "$EVAL_RESULT_DIR does not exists"
    exit 1
fi

if ! ls "$EVAL_RESULT_DIR"/*/scripts > /dev/null ; then
    echo "$EVAL_RESULT_DIR seems to be not a directory created via the run-eval.sh script"
    exit 1
fi


# Update the scripts with local version
for target in "$EVAL_RESULT_DIR"/*/scripts; do
    echo "=> Updating scripts at $target"
    rsync -a "$FISH_FUZZ_ROOT/paper/artifact/two-stage/scripts/" $target
done

# Copy per target results for each individual repetition into one folder.
for run_dir in "$EVAL_RESULT_DIR"/*; do
    if echo $run_dir | grep -q "collected-runs"; then
        continue
    fi
    run_name="$(basename $run_dir)"
    run_id="$(echo $run_name | cut -d '-' -f 4 )"
    if [[ -z "$run_id" ]]; then
        continue
    fi

    dst_dir="$EVAL_RESULT_DIR/collected-runs-$run_id"
    rsync -a "$run_dir/"* "$dst_dir"
done

function compute_coverage() {
    set -eu
    readonly run_dir="$1"
    if [[ -z "$run_dir" ]]; then
        return
    fi
    ./postprocess.sh "$run_dir"
}
export -f compute_coverage

args=""
# Build that arguments for parallel
for collected_run_dir in "$EVAL_RESULT_DIR"/collected-runs-* ; do
    args="$collected_run_dir\0$args"
done

echo -ne $args | parallel -j $CPUS --bar -kd'\0' -- compute_coverage {} ';' || true