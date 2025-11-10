#!/bin/bash

source /venv/main/bin/activate
COMFYUI_DIR=${WORKSPACE}/ComfyUI

# Packages are installed after nodes so we can fix them...

APT_PACKAGES=(
    #"package-1"
    #"package-2"
)

PIP_PACKAGES=(
    #"package-1"
    #"package-2"
)

NODES=(
    #"https://github.com/ltdrdata/ComfyUI-Manager"
    #"https://github.com/cubiq/ComfyUI_essentials"
	"https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
 	"https://github.com/kijai/ComfyUI-KJNodes"
  	"https://github.com/sipherxyz/comfyui-art-venture"
    "https://github.com/rgthree/rgthree-comfy"
	"https://github.com/city96/ComfyUI-GGUF"
 	"https://github.com/BuddyMario/ComfyS3"
    #"https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler"
 )

WORKFLOWS=(

)

CHECKPOINT_MODELS=(
)

UNET_MODELS=(
)

LORA_MODELS=(
)

VAE_MODELS=(
)

ESRGAN_MODELS=(
)

CONTROLNET_MODELS=(
)

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

function provisioning_start() {
    provisioning_print_header
	provisioning_install_cylindria
    provisioning_get_apt_packages
    provisioning_get_pip_packages
	provisioning_custom_steps
    provisioning_get_nodes
    provisioning_get_files \
        "${COMFYUI_DIR}/models/checkpoints" \
        "${CHECKPOINT_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/unet" \
        "${UNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/lora" \
        "${LORA_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/controlnet" \
        "${CONTROLNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/vae" \
        "${VAE_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/esrgan" \
        "${ESRGAN_MODELS[@]}"
    provisioning_restart_supervisor
    provisioning_print_end
}

function provisioning_install_cylindria()
{
	cd /workspace/
    git clone https://BuddyMario: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@github.com/BuddyMario/Cylindria.git
	cd /workspace/Cylindria
    cp ./log_conf/cylindria /etc/logrotate.d/
	sudo chown root:root /etc/logrotate.d/cylindria
    sudo chmod 0644 /etc/logrotate.d/cylindria
 	pip install -r requirements.txt
    cp /workspace/Cylindria/config_files/cylindria.sh /opt/supervisor-scripts/
    sudo chmod +x /opt/supervisor-scripts/cylindria.sh
    cp /workspace/Cylindria/config_files/cylindria.conf /etc/supervisor/conf.d/
    export COMFYUI_BASE_URL="http://127.0.0.1:18188"
#    nohup python -m cylindria --port 8100 > cylindria.log 2>&1 < /dev/null & disown

}

function provisioning_get_apt_packages() {
    if [[ -n $APT_PACKAGES ]]; then
            sudo $APT_INSTALL ${APT_PACKAGES[@]}
    fi
}

function provisioning_get_pip_packages() {
    if [[ -n $PIP_PACKAGES ]]; then
            pip install --no-cache-dir ${PIP_PACKAGES[@]}
    fi
}

function provisioning_get_nodes() {
    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        path="${COMFYUI_DIR}/custom_nodes/${dir}"
        requirements="${path}/requirements.txt"
        if [[ -d $path ]]; then
            if [[ ${AUTO_UPDATE,,} != "false" ]]; then
                printf "Updating node: %s...\n" "${repo}"
                ( cd "$path" && git pull )
                if [[ -e $requirements ]]; then
                   pip install --no-cache-dir -r "$requirements"
                fi
            fi
        else
            printf "Downloading node: %s...\n" "${repo}"
            git clone "${repo}" "${path}" --recursive
            if [[ -e $requirements ]]; then
                pip install --no-cache-dir -r "${requirements}"
            fi
        fi
    done
}

function provisioning_get_files() {
    if [[ -z $2 ]]; then return 1; fi
    
    dir="$1"
    mkdir -p "$dir"
    shift
    arr=("$@")
    printf "Downloading %s model(s) to %s...\n" "${#arr[@]}" "$dir"
    for url in "${arr[@]}"; do
        printf "Downloading: %s\n" "${url}"
        provisioning_download "${url}" "${dir}"
        printf "\n"
    done
}

function provisioning_print_header() {
    printf "\n##############################################\n#                                            #\n#          Provisioning container            #\n#                                            #\n#         This will take some time           #\n#                                            #\n# Your container will be ready on completion #\n#                                            #\n##############################################\n\n"
	touch /.initializing
}

function provisioning_print_end() {
    printf "\nProvisioning complete:  Application will start now\n\n"
	rm /.initializing
}

function provisioning_restart_supervisor
{
    echo "Restarting supervisor to apply changes..."
    sudo supervisorctl reread
    sudo supervisorctl update
    sudo supervisorctl restart
    sleep 30
}

function provisioning_has_valid_hf_token() {
    [[ -n "$HF_TOKEN" ]] || return 1
    url="https://huggingface.co/api/whoami-v2"

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $HF_TOKEN" \
        -H "Content-Type: application/json")

    # Check if the token is valid
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

function provisioning_has_valid_civitai_token() {
    [[ -n "$CIVITAI_TOKEN" ]] || return 1
    url="https://civitai.com/api/v1/models?hidden=1&limit=1"

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $CIVITAI_TOKEN" \
        -H "Content-Type: application/json")

    # Check if the token is valid
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

# Download from $1 URL into a base dir $2, preserving HF subfolders when possible.
# Optional $3 controls wget dot progress granularity (default 4M).
provisioning_download() {
  local url="$1" base_dir="$2" dotbytes="${3:-100M}"
  local auth_token="" host="" subpath="" dest_dir="" filename=""

  # Auth token selection (HF/Civitai)
  if [[ -n ${HF_TOKEN:-} && $url =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co(/|$|\?) ]]; then
    auth_token="$HF_TOKEN"
  elif [[ -n ${CIVITAI_TOKEN:-} && $url =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com(/|$|\?) ]]; then
    auth_token="$CIVITAI_TOKEN"
  fi

  # 1) Compute relative subpath for Hugging Face "resolve/main" URLs:
  #    e.g., https://huggingface.co/.../resolve/main/Wan2.1/i2v_14B_480/wan-thiccum-v3.safetensors
  #          -> subpath="Wan2.1/i2v_14B_480"
  if [[ $url == *"/resolve/main/"* ]]; then
    subpath="${url#*resolve/main/}"     # "Wan2.1/i2v_14B_480/wan-thiccum-v3.safetensors?download=true"
    subpath="${subpath%%\?*}"           # strip query
    subpath="${subpath%/*}"             # drop filename -> "Wan2.1/i2v_14B_480"
  else
    subpath=""                           # unknown host layout -> flat
  fi

  # 2) Destination directory
  if [[ -n $subpath ]]; then
    dest_dir="${base_dir%/}/${subpath}"
  else
    dest_dir="${base_dir%/}"
  fi
  mkdir -p "$dest_dir"

  # 3) Derive filename (avoid surprises if --content-disposition renames things)
  filename="${url##*/}"
  filename="${filename%%\?*}"

  # 4) Download
  if [[ -n $auth_token ]]; then
    # Use -O to enforce the expected filename, regardless of Content-Disposition.
    wget --header="Authorization: Bearer $auth_token" \
         -qnc --show-progress --content-disposition \
         -e "dotbytes=${dotbytes}" -O "${dest_dir}/${filename}" "$url"
  else
    wget -qnc --show-progress --content-disposition \
         -e "dotbytes=${dotbytes}" -O "${dest_dir}/${filename}" "$url"
  fi
}

provisioning_custom_steps()
{
   	cd /workspace/
    git clone https://BuddyMario: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@github.com/BuddyMario/VastaiFiles.git

    cp /workspace/VastaiFiles/comfyui.sh /opt/supervisor-scripts/
    sudo chmod +x /opt/supervisor-scripts/comfyui.sh

    cp /workspace/VastaiFiles/comfyui2.conf /etc/supervisor/conf.d/
    cp /workspace/VastaiFiles/comfyui3.conf /etc/supervisor/conf.d/
    cp /workspace/VastaiFiles/comfyui4.conf /etc/supervisor/conf.d/

	# Download the dataset
	hf download "BloodyMario/CloudLoras" --local-dir "/workspace/ComfyUI/models/loras" --repo-type dataset --token "$HF_TOKEN"
	
	hf download "BloodyMario/ConfigFiles" --local-dir "/workspace/ConfigFiles" --repo-type dataset --token "$HF_TOKEN"
	
	pip install -r /workspace/ConfigFiles/accelerated_270_312.txt
	
	wget https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors -P /workspace/ComfyUI/models/vae -qnc --show-progress --progress=bar:force
	wget https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors -P /workspace/ComfyUI/models/text_encoders -qnc --show-progress --progress=bar:force
	
	wget https://huggingface.co/bullerwins/Wan2.2-I2V-A14B-GGUF/resolve/main/wan2.2_i2v_high_noise_14B_Q8_0.gguf -P /workspace/ComfyUI/models/diffusion_models -qnc --show-progress --progress=bar:force
	wget https://huggingface.co/bullerwins/Wan2.2-I2V-A14B-GGUF/resolve/main/wan2.2_i2v_low_noise_14B_Q8_0.gguf -P /workspace/ComfyUI/models/diffusion_models -qnc --show-progress --progress=bar:force
}

# Allow user to disable provisioning if they started with a script they didn't want
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
