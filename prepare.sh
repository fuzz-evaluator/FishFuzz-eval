set -e
set -o pipefail

DIR="$(dirname $(readlink -f $0))"
source $DIR/config.sh


# Build the image
pushd $DIR/FishFuzz-upstream/paper/artifact/two-stage/ >/dev/null

# Mount the FishFuzz source into the Docker build context, such that
# the it can be copied into the image during build.
if mountpoint "$PWD/FishFuzz-upstream"; then
    sudo umount "$PWD/FishFuzz-upstream"
fi
mkdir -p $PWD/FishFuzz-upstream
sudo mount -o ro,bind "$DIR/FishFuzz-upstream" "$PWD/FishFuzz-upstream"
sudo docker build -t $TWO_STAGE_ARTIFACT_DOCKER_IMAGE_NAME .
sudo umount "$PWD/FishFuzz-upstream"

popd >/dev/null

# Prepare the environment 
echo core | sudo tee /proc/sys/kernel/core_pattern
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor