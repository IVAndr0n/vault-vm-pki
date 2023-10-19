#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Name:           03-vault-withoutTLS-autounseal.sh
# Description:    Automatic Unseal Vault without TLS
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

# Setting Vault Auto Unseal
echo "Set vault-auto-unseal Script"
tee ${vault_dir_config}/${vault_file_unseal_script} >/dev/null <<EOF
#!/usr/bin/env bash
set -x
${vault_file_unseal_log}
export VAULT_ADDR=http://${vault_server_fqdn}:8200
export VAULT_SKIP_VERIFY=true
export VAULT_NAMESPACE=${namespace_vault}
vault operator unseal \$(grep 'Key 1:' ${vault_dir_config}/${vault_file_keys} | awk '{print \$NF}')
vault operator unseal \$(grep 'Key 2:' ${vault_dir_config}/${vault_file_keys} | awk '{print \$NF}')
vault operator unseal \$(grep 'Key 3:' ${vault_dir_config}/${vault_file_keys} | awk '{print \$NF}')
export ROOT_TOKEN=\$(grep 'Initial Root Token:' ${vault_dir_config}/${vault_file_keys} | awk '{print \$NF}')
export VAULT_TOKEN=\${ROOT_TOKEN}
vault login \${ROOT_TOKEN}
EOF

chmod 0755 ${vault_dir_config}/${vault_file_unseal_script}

# Add vault_auto_unseal Service
read -d '' vault_auto_unseal_service <<EOF
[Unit]
Description=Vault Auto Unseal Service
Requires=vault.service
After=vault.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 10
ExecStart=/bin/bash ${vault_dir_config}/${vault_file_unseal_script}
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

if command -v yum >/dev/null 2>&1; then
  echo "Installing systemd services for RHEL/CentOS"
  system_dir=/etc/systemd/system
  echo "${vault_auto_unseal_service}" | sudo tee ${system_dir}/vault_auto_unseal.service
  sudo chmod 0644 ${system_dir}/vault_auto_unseal*
elif command -v apt >/dev/null 2>&1; then
  echo "Installing systemd services for Debian/Ubuntu"
  system_dir=/lib/systemd/system
  echo "${vault_auto_unseal_service}" | sudo tee ${system_dir}/vault_auto_unseal.service
  sudo chmod 0644 ${system_dir}/vault_auto_unseal*
else
  echo "Service not installed due to OS detection failure"
  exit 1
fi

# Enable Autostart vault_auto_unseal Service
sudo systemctl daemon-reload
sudo systemctl enable vault_auto_unseal
