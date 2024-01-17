#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Name:           01-install-vault-in-vm.sh
# Description:    Installation and initial configuration of the Vault
# Code revision:  Andrey Eremchuk, https://github.com/IVAndr0n/
# ------------------------------------------------------------------------------
set -o xtrace

# Checking if a file with variables exists in the current directory
variables=config.env
location="$(cd "$(dirname -- "$0")" && pwd -P)"

if [ -f "${location}/${variables}" ]; then
    echo "Loading variables from a ${variables} file"
    . "${location}/${variables}"
else
    echo "The ${variables} file was not found."
    exit 1
fi

# Function to install required components in RHEL/CentOS
install_prerequisites_rhel() {
  echo "Perform updates and install prerequisites"
  sudo yum-config-manager --enable rhui-REGION-rhel-server-releases-optional
  sudo yum-config-manager --enable rhui-REGION-rhel-server-supplementary
  sudo yum-config-manager --enable rhui-REGION-rhel-server-extras
  sudo yum -y check-update

  for package in "${required_packages_rhel[@]}"; do
    if ! command -v "${package}" >/dev/null 2>&1; then
      sudo yum install -q -y "${package}"
    fi
  done

  sudo systemctl start ntpd.service
  sudo systemctl enable ntpd.service
  sudo timedatectl set-timezone UTC
}

# Function to install required components in Debian/Ubuntu
install_prerequisites_ubuntu() {
  echo "Perform updates and install prerequisites"
  sudo apt -qq -y update

  for package in "${required_packages_ubuntu[@]}"; do
    if ! command -v "${package}" >/dev/null 2>&1; then
      sudo apt install -qq -y "${package}"
    fi
  done

  sudo systemctl start ntp.service
  sudo systemctl enable ntp.service
  sudo timedatectl set-timezone UTC
  echo "Disable reverse DNS lookup in SSH"
  sudo sh -c 'echo "\nUseDNS no" >> /etc/ssh/sshd_config'
  sudo service ssh restart
}

# Function to add user to RHEL/CentOS
user_rhel() {
  echo "Creating user '${vault_user_name}'"
  sudo /usr/sbin/groupadd --force --system ${vault_user_group}
  if ! getent passwd ${vault_user_name} >/dev/null; then
    sudo /usr/sbin/adduser \
      --system \
      --gid ${vault_user_group} \
      --home ${vault_user_home} \
      --no-create-home \
      --comment "${vault_user_comment}" \
      --shell /bin/false \
      ${vault_user_name} >/dev/null
  fi
}

# Function to add user to Debian/Ubuntu
user_ubuntu() {
  echo "Creating user '${vault_user_name}'"
  if ! getent group ${vault_user_group} >/dev/null; then
    sudo addgroup --system ${vault_user_group} >/dev/null
  fi
  if ! getent passwd ${vault_user_name} >/dev/null; then
    sudo adduser \
      --system \
      --disabled-login \
      --ingroup ${vault_user_group} \
      --home ${vault_user_home} \
      --no-create-home \
      --gecos "${vault_user_comment}" \
      --shell /bin/false \
      ${vault_user_name} >/dev/null
  fi
}

if command -v yum >/dev/null 2>&1; then
  echo "RHEL/CentOS system detected"
  install_prerequisites_rhel
  user_rhel
elif command -v apt >/dev/null 2>&1; then
  echo "Debian/Ubuntu system detected"
  install_prerequisites_ubuntu
  user_ubuntu
else
  echo "Prerequisites not installed and user not created due to OS detection failure"
  exit 1
fi

# Download Vault
echo "Download Vault"
curl -o ${download_dir}/${vault_zip} -fsSL ${vault_url} || {
  echo "Failed to download Vault ${vault_version}"
  exit 1
}

# Install Vault
echo "Installing Vault ${vault_version}"
sudo unzip -o ${download_dir}/${vault_zip} -d ${vault_dir_bin}
sudo chmod 0755 ${vault_dir_bin}/${vault_file_bin}

echo "Granting mlock syscall to vault binary"
sudo setcap cap_ipc_lock=+ep ${vault_dir_bin}/${vault_file_bin}

echo "$(${vault_dir_bin}/${vault_file_bin} --version)"

# Configuration Vault
echo "We create directories and assign the necessary security rights"
sudo mkdir -pm 0700 ${vault_dir_data} ${vault_dir_logs}
sudo chown ${vault_user_name}:${vault_user_group} ${vault_dir_data} ${vault_dir_logs}

sudo mkdir -pm 0755 ${vault_dir_config}
sudo chown ${USER}:$(id -gn ${USER}) ${vault_dir_config}

echo "Configuring Vault ${vault_version}"
tee ${vault_dir_config}/${vault_file_config} <<EOF
listener "tcp" {
  address               = "0.0.0.0:8200"
  tls_disable           = 1
}
storage "file" {
    path                = "${vault_dir_data}"
}
ui                      = true
disable_mlock           = true
log_level               = "error"
api_addr                = "http://${vault_server_fqdn}:8200"
EOF

# Install Vault Systemd Service
read -d '' vault_service <<EOF
[Unit]
Description=Vault Service
Requires=network-online.target
After=network-online.target

[Service]
Restart=on-failure
PermissionsStartOnly=true
ExecStartPre=/sbin/setcap 'cap_ipc_lock=+ep' ${vault_dir_bin}/${vault_file_bin}
ExecStart=${vault_dir_bin}/${vault_file_bin} server -config ${vault_dir_config}
ExecReload=/bin/kill -HUP \$MAINPID
KillSignal=SIGTERM
User=${vault_user_name}
Group=${vault_user_group}

[Install]
WantedBy=multi-user.target
EOF

if command -v yum >/dev/null 2>&1; then
  echo "Installing systemd services for RHEL/CentOS"
  system_units=/etc/systemd/system
  echo "${vault_service}" | sudo tee ${system_units}/vault.service
  sudo chmod 0644 ${system_units}/vault*
elif command -v apt >/dev/null 2>&1; then
  echo "Installing systemd services for Debian/Ubuntu"
  system_units=/etc/systemd/system
  echo "${vault_service}" | sudo tee ${system_units}/vault.service
  sudo chmod 0644 ${system_units}/vault*
else
  echo "Service not installed due to OS detection failure"
  exit 1
fi

# Start Vault Service
sudo systemctl daemon-reload
sudo systemctl enable --now vault.service
systemctl status vault.service

sleep 5
export VAULT_ADDR=http://${vault_server_fqdn}:8200
export VAULT_SKIP_VERIFY=true
export VAULT_NAMESPACE=${namespace_vault}

vault status
