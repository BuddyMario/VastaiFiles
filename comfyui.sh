#!/bin/bash

# User can configure startup by removing the reference in /etc.portal.yaml - So wait for that file and check it
while [ ! -f "$(realpath -q /etc/portal.yaml 2>/dev/null)" ]; do
    echo "Waiting for /etc/portal.yaml before starting ${PROC_NAME}..." | tee -a "/var/log/portal/${PROC_NAME}.log"
    sleep 1
done

# requested device id (default 0 if none passed)
DEVICE_ID="${1:-0}"

echo "Device Id: ${DEVICE_ID}"

# derive port from device id
BASE_PORT=18188
PORT=$((BASE_PORT + DEVICE_ID))

echo "Port: ${PORT}"

# count available CUDA devices
NUM_DEVICES=$(nvidia-smi -L | wc -l)

# validate device id
if [ "$DEVICE_ID" -ge "$NUM_DEVICES" ]; then
    echo "Requested CUDA device $DEVICE_ID but only $NUM_DEVICES device(s) available. Exiting."
    exit 0
fi

# Activate the venv
. /venv/main/bin/activate

# Wait for provisioning to complete

while [ -f "/.provisioning" ]; do
    echo "$PROC_NAME startup paused until instance provisioning has completed (/.provisioning present)"
    sleep 10
done

export S3_REGION=auto
export S3_ACCESS_KEY=90e80e3a8f4dbdbf262fd5cba598ea28
export S3_BUCKET_NAME=chatpic-videos    
export S3_ENDPOINT_URL=https://de43a759ac9d300a66733e5cfedcc481.r2.cloudflarestorage.com
export S3_INPUT_DIR=Images
export S3_OUTPUT_DIR=Videos

# Avoid git errors because we run as root but files are owned by 'user'
export GIT_CONFIG_GLOBAL=/tmp/temporary-git-config
git config --file $GIT_CONFIG_GLOBAL --add safe.directory '*'

echo "Launching ComfyUI --disable-auto-launch --port $PORT --enable-cors-header --cuda-device $DEVICE_ID"

# Launch ComfyUI
cd ${WORKSPACE}/ComfyUI
LD_PRELOAD=libtcmalloc_minimal.so.4 \
        python main.py \
        --disable-auto-launch --port "${PORT}" --enable-cors-header --cuda-device "${DEVICE_ID}" 2>&1 | tee -a "/var/log/portal/${PROC_NAME}.log"
