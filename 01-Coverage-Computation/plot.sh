#!/bin/bash

set -e
DIR="$(dirname "$(readlink -f $0)")"
ROOT_DIR="$(readlink -f "$DIR/..")"
source "$ROOT_DIR/config.sh"

./prepare.sh

docker run --rm --user $(id -u):$(id -g) --workdir /data/01-Coverage-Computation/scripts -it -v $ROOT_DIR:/data fishfuzz-01 python3 plot_runs.py