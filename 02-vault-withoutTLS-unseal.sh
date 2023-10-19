#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Name:           02-vault-withoutTLS-unseal.sh
# Description:    Unseal Vault without TLS
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

# Unseal Vault
echo "Unseal Vault"
sleep 5
export VAULT_ADDR=http://${vault_server_fqdn}:8200
export VAULT_SKIP_VERIFY=true
export VAULT_NAMESPACE=${namespace_vault}

vault operator init >${vault_dir_config}/${vault_file_keys}

vault operator unseal $(grep 'Key 1:' ${vault_dir_config}/${vault_file_keys} | awk '{print $NF}')
vault operator unseal $(grep 'Key 2:' ${vault_dir_config}/${vault_file_keys} | awk '{print $NF}')
vault operator unseal $(grep 'Key 3:' ${vault_dir_config}/${vault_file_keys} | awk '{print $NF}')

export ROOT_TOKEN=$(grep 'Initial Root Token:' ${vault_dir_config}/${vault_file_keys} | awk '{print $NF}')
vault login ${ROOT_TOKEN}

vault status

# Enable Audit
if [ "${vault_audit_enable}" = true ]; then
     # Enable audit and write logs to a file
     vault audit enable file file_path=${vault_dir_logs}/${vault_file_audit_log}
     # Enable raw audit and write logs to a file
     vault audit enable -path=file_raw file log_raw=true file_path=${vault_dir_logs}/${vault_file_audit_raw_log}

     vault audit list -detailed
fi
