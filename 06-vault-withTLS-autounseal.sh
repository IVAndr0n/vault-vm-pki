#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Name:           06-vault-withTLS-autounseal.sh
# Description:    Automatic Unseal Vault with TLS
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

rm -r ${vault_dir_config}/${vault_file_config}
rm -r ${vault_dir_config}/${vault_file_unseal_script}

# Configuration Vault with TLS
echo "Configuring Vault ${vault_version}"
tee ${vault_dir_config}/${vault_file_config} <<EOF
listener "tcp" {
  address               = "0.0.0.0:8200"
  tls_disable           = 0
  tls_cert_file         = "${vault_dir_tls}/${ca_cert_file_name_vault_server}.pem"
  tls_key_file          = "${vault_dir_tls}/${ca_key_file_name_vault_server}.key"
  tls_client_ca_file    = "${vault_dir_crt}/${ca_cert_file_name_intermediate}.pem"
}
storage "file" {
    path                = "${vault_dir_data}"
}
ui                      = true
disable_mlock           = true
log_level               = "error"
api_addr                = "https://${vault_server_fqdn}:8200"
EOF

# Setting Vault Auto Unseal with TLS
echo "Set vault-auto-unseal Script"
tee ${vault_dir_config}/${vault_file_unseal_script} >/dev/null <<EOF
#!/usr/bin/env bash
set -x
${vault_file_unseal_log}
export VAULT_ADDR=https://${vault_server_fqdn}:8200
export VAULT_SKIP_VERIFY=false
export VAULT_NAMESPACE=${namespace_vault}
export VAULT_CACERT=${vault_dir_crt}/${ca_cert_file_name_intermediate}.pem
vault operator unseal \$(grep 'Key 1:' ${vault_dir_config}/${vault_file_keys} | awk '{print \$NF}')
vault operator unseal \$(grep 'Key 2:' ${vault_dir_config}/${vault_file_keys} | awk '{print \$NF}')
vault operator unseal \$(grep 'Key 3:' ${vault_dir_config}/${vault_file_keys} | awk '{print \$NF}')
export ROOT_TOKEN=\$(grep 'Initial Root Token:' ${vault_dir_config}/${vault_file_keys} | awk '{print \$NF}')
export VAULT_TOKEN=\${ROOT_TOKEN}
vault login \${ROOT_TOKEN}
EOF

echo "Lowering security rights"
sudo chmod -R 0555 ${vault_dir_crt}
sudo chown -R ${vault_user_name}:${vault_user_group} ${vault_dir_crt}

sudo chmod -R 0500 ${vault_dir_tls}
sudo chown -R ${vault_user_name}:${vault_user_group} ${vault_dir_tls}

sudo chmod -R 0500 ${vault_dir_config}
sudo chown -R ${vault_user_name}:${vault_user_group} ${vault_dir_config}

sudo chmod 0400 ${vault_dir_config}/${vault_file_config}
sudo chmod 0400 ${vault_dir_config}/${vault_file_keys}

sudo systemctl restart vault.service
sudo systemctl restart vault_auto_unseal.service

# I recommend rebooting, after which file '.vault-token' will be generated in the root user profile
# The file contains a root token, this is a security risk. I think so at the moment, maybe I'm wrong :)
rm -r ~/.vault-token
