#!/bin/bash

# Throw warning if script is not executed as root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root to set up the service correctly"
    echo "Run it like this:"
    echo "sudo ./download.sh"
    exit 1
fi

mkdir -p /etc/wingbits

if [[ -e /etc/wingbits/device ]]; then
    read -r device_id < /etc/wingbits/device
fi

if [[ -z ${device_id} ]]; then
    read -p "Enter the device ID: " device_id </dev/tty
    echo "$device_id" > /etc/wingbits/device
fi

echo "Using device ID: $device_id"

# possible they just hit enter above or the file is empty
if [[ -z ${device_id} ]]; then
    echo "You need to add the device id that you got in the email"
    exit 1
else
    grep -qxF "DEVICE_ID=\"$device_id\"" /etc/default/vector || echo "DEVICE_ID=\"$device_id\"" >> /etc/default/vector
    echo "Device ID saved to local config file /etc/wingbits/device"
fi

# Function to display loading animation with an airplane icon
function show_loading() {
  local text=$1
  local delay=0.2
  local frames=("â£¾" "â£½" "â£»" "â¢¿" "â¡¿" "â£Ÿ" "â£¯" "â£·")
  local frame_count=${#frames[@]}
  local i=0

  while true; do
    local frame_index=$((i % frame_count))
    printf "\r%s  %s" "${frames[frame_index]}" "${text}"
    sleep $delay
    i=$((i + 1))
  done
}

# Function to run multiple commands and log the output
function run_command() {
  local commands=("$@")
  local text=${commands[0]}
  local command
  echo "===================${text}====================" >> /tmp/wingbits.log

  for command in "${commands[@]:1}"; do
    (
      eval "${command}" >> /tmp/wingbits.log 2>&1
      printf "done" > /tmp/wingbits.done
    ) &
    local pid=$!

    show_loading "${text}" &
    local spinner_pid=$!

    # Wait for the command to finish
    wait "${pid}"

    # Kill the spinner
    kill "${spinner_pid}"
    wait "${spinner_pid}" 2>/dev/null

    # Check if the command completed successfully
    if [[ -f /tmp/wingbits.done ]]; then
      rm /tmp/wingbits.done
      printf "\r\033[0;32mâœ“\033[0m   %s\n" "${text}"
    else
      printf "\r\033[0;31mâœ—\033[0m   %s\n" "${text}"
    fi
  done
}

function check_service_status(){
  local services=("vector")
  for service in "${services[@]}"; do
    status="$(systemctl is-active "$service".service)"
    if [ "$status" != "active" ]; then
        echo "$service is inactive. Waiting 5 seconds..."
        sleep 5
        status="$(systemctl is-active "$service".service)"
        if [ "$status" != "active" ]; then
            echo "$service is still inactive."
        else
            echo "$service is now active. âœˆ"
        fi
    else
        echo "$service is active. âœˆ"
    fi
  done
}
# Step 1: Update package repositories
run_command "Updating package repositories" "apt-get update"

# Step 2: Upgrade installed packages
run_command "Upgrading installed packages" "apt-get upgrade -y"

# Step 3: Install curl if not already installed
run_command "Installing curl" "apt-get -y install curl"

# Step 4: Download and install Vector
run_command "Installing vector" \
  "curl -1sLf 'https://repositories.timber.io/public/vector/cfg/setup/bash.deb.sh' | sudo -E bash" \
  "apt-get -y install vector" \
  "mkdir -p /etc/vector" \
  "touch /etc/vector/vector.yaml" \
  "curl -o /etc/vector/vector.yaml 'https://gitlab.com/wingflyer1/my-wingbits-code/-/blob/main/config/raw/master/vector.yaml'" \
  "sed -i 's|ExecStart=.*|ExecStart=/usr/bin/vector --watch-config|' /lib/systemd/system/vector.service" \
  "echo \"DEVICE_ID=\\\"$device_id\\\"\" | sudo tee -a /etc/default/vector > /dev/null"

# Step 5: Reload systemd daemon, enable and start services
run_command "Starting services" \
  "systemctl daemon-reload" \
  "systemctl enable vector" \
  "systemctl start vector"

# Step 6: Create the check status cron job
echo '#!/bin/bash
STATUS="$(systemctl is-active vector.service)"

if [ "$STATUS" != "active" ]; then
    systemctl restart vector.service
    echo "$(date): Service was restarted" >> /tmp/wingbits.log
fi' > /etc/wingbits/check_status.sh && \
sudo chmod +x /etc/wingbits/check_status.sh && \
echo "*/5 * * * * root /bin/bash /etc/wingbits/check_status.sh" | sudo tee /etc/cron.d/wingbits

echo -e "\n\033[0;32mInstallation completed successfully!\033[0m"

# Step 8: Check if services are online
check_service_status
