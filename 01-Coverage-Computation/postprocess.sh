#!/bin/bash

#
# Process the results of the fuzzing runs started via the commands emitted
# by the `generate_fuzz_cmd.sh` script.
# The processing done in this script happens according to the original artifact
# (i.e., coverage computation via ffafl binary).
#

set -eu
set -o pipefail

DIR="$(dirname "$(readlink -f $0)")"
ROOT_DIR="$(readlink -f "$DIR/..")"
source "$ROOT_DIR/config.sh"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <path-to-workdir>"
    exit 1
fi
readonly WORK_DIR="$1"

if [[ ! -d "$WORK_DIR/runtime" ]]; then
    echo "$WORK_DIR does not contain a runtime folder, is the target directory correct?"
    exit 1
fi

# The fuzzing results (as produced by the fuzzers)
FUZZING_RESULT="$WORK_DIR/runtime"

# The fuzzing results copied via copy_results.py
FUZZING_RESULT_COPIED="$WORK_DIR/results"

# The coverage results
COV_RESULT_DIR="$WORK_DIR/coverage"

if [[ -d "$FUZZING_RESULT_COPIED" ]]; then
    rm -rf "$FUZZING_RESULT_COPIED"
fi

mkdir -p "$COV_RESULT_DIR"
mkdir -p "$FUZZING_RESULT_COPIED"

# Fix permission of files created by the container.
sudo chown -R "$(id -u):$(id -g)" "$WORK_DIR/"

# Make a copy of the fuzzing results, since the copy_results.py script does actually move the data and
# is therefore destructive.
tmp_result_dir=$(mktemp -d)
rsync -a "$FUZZING_RESULT/out" "$tmp_result_dir"

# Copy queue files and crashes
python3 "$WORK_DIR/scripts/copy_results.py" -s "$tmp_result_dir" -d "$FUZZING_RESULT_COPIED/" -r 0
rm -rf "$tmp_result_dir"


container_id=$(docker run -td --rm -v "$FUZZING_RESULT_COPIED:/results" -v "$WORK_DIR/scripts:/scripts" -v "$COV_RESULT_DIR:/coverage"  "$TWO_STAGE_ARTIFACT_DOCKER_IMAGE_NAME" bash)
echo "container_id=$container_id"

docker exec "$container_id" bash -c 'apt update && apt install python3-pip -y && pip3 install progress'

# These may fail because no such file exists. However, these are required in order for `analysis.py`` to work.
docker exec "$container_id" bash -c 'find /results -name README.txt -exec rm {} \;' || true
docker exec "$container_id" bash -c 'find /results -name .state -exec rm -r {} \;' || true
docker exec "$container_id" bash -c 'find /results -name others -exec rm -r {} \;' || true

##########################################################

# if [[ -d "$COV_RESULT_DIR/AFL-map-size-18" ]]; then
#     echo "=> Skipping afl-map-size-18 coverage since $COV_RESULT_DIR/AFL-map-size-18 already exists"
# else
#     # Compute coverage using AFL binaries with a bitmap of size 18
#     # Replace /binary/ffafl with /binary/afl-map-size-18
#     docker exec -i "$container_id" bash -c 'sed "s@/binary/ffafl@/binary/afl-map-size-18@" /scripts/analysis.py > /tmp/analysis_afl.py'

#     # replace /FishFuzz/afl-showmap with /AFL-map-size-18/afl-showmap
#     docker exec -i "$container_id" bash -c 'sed -i "s@/FishFuzz/afl-showmap@/AFL-map-size-18/afl-showmap@" /tmp/analysis_afl.py'

#     # Replace bitmap size
#     docker exec -i "$container_id" bash -c 'sed -i "s@self\.MAP_SIZE.*=.*@self\.MAP_SIZE = 1 << 18@" /tmp/analysis_afl.py'

#     # Compute coverage based on all files, not only those with a +cov infix.
#     docker exec -i "$container_id" bash -c 'sed -i "s@if __seed_dict\[_time\]\.find.*@if False:@" /tmp/analysis_afl.py'
#     docker exec -i "$container_id" bash -c 'python3 /tmp/analysis_afl.py -b /results -c /scripts/asan.queue.json -r 0 -d /results/log/'
#     docker exec -i "$container_id" bash -c 'python3 /tmp/analysis_afl.py -b /results -c /scripts/asan.crash.json -r 0 -d /results/log/'
#     docker exec -i "$container_id" bash -c 'mv /results/log /coverage/AFL-map-size-18'
# fi

##########################################################

if [[ -d "$COV_RESULT_DIR/ffafl" ]]; then
    echo "=> Skipping ffafl coverage since $COV_RESULT_DIR/ffafl already exists"
else
    # Compute coverage using AFL binaries that additionally contain instrumentation specific to FishFuzz
    docker exec -i "$container_id" bash -c 'python3 /scripts/analysis.py -b /results -c /scripts/asan.queue.json -r 0 -d /results/log/'
    docker exec -i "$container_id" bash -c 'python3 /scripts/analysis.py -b /results -c /scripts/asan.crash.json -r 0 -d /results/log/'
    docker exec -i "$container_id" bash -c 'mv /results/log /coverage/ffafl'
fi

##########################################################

if [[ -d "$COV_RESULT_DIR/afl" ]]; then
    echo "=> Skipping afl coverage since $COV_RESULT_DIR/afl already exists"
else
    # Compute coverage using AFL binaries *without* additional FishFuzz instrumentation.
    # Replace /binary/ffafl with /binary/afl
    docker exec -i "$container_id" bash -c 'sed "s@/binary/ffafl@/binary/afl@" /scripts/analysis.py > /tmp/analysis_afl.py'
    # Compute coverage based on all files, not only those with a +cov infix.
    docker exec -i "$container_id" bash -c 'sed -i "s@if __seed_dict\[_time\]\.find.*@if False:@" /tmp/analysis_afl.py'
    docker exec -i "$container_id" bash -c 'python3 /tmp/analysis_afl.py -b /results -c /scripts/asan.queue.json -r 0 -d /results/log/'
    docker exec -i "$container_id" bash -c 'python3 /tmp/analysis_afl.py -b /results -c /scripts/asan.crash.json -r 0 -d /results/log/'
    docker exec -i "$container_id" bash -c 'mv /results/log /coverage/afl'
fi

##########################################################

docker rm -f "$container_id"
sudo chown -R "$(id -u):$(id -g)" "$WORK_DIR/"