#!/bin/bash

#
# Prepare this experiment
#
set -eu
set -o pipefail

DIR="$(dirname "$(readlink -f $0)")"
ROOT_DIR="$(readlink -f "$DIR/..")"
source "$ROOT_DIR/config.sh"

# Prepare the environment.
echo core | sudo tee /proc/sys/kernel/core_pattern
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

docker build -t fishfuzz-01 --build-arg TWO_STAGE_ARTIFACT_DOCKER_IMAGE_NAME="$TWO_STAGE_ARTIFACT_DOCKER_IMAGE_NAME" .
