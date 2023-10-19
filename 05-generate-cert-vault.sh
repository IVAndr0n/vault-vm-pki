#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Name:           05-generate-cert-vault.sh
# Description:    We create a certificate for direct use by the Vault server itself
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

# 06_generate_certificate_for_Vault_server
export VAULT_ADDR=http://${vault_server_fqdn}:8200
export VAULT_SKIP_VERIFY=true
export VAULT_NAMESPACE=${namespace_vault}

# We generate a user token, use it for authorization
export VAULT_TOKEN=$(vault login -token-only -method=userpass \
  username=${pki_access_user_name} \
  password=${pki_access_user_name_password})

echo "We create directories and assign the necessary security rights"
sudo mkdir -pm 0755 ${vault_dir_tls}
sudo chown ${USER}:$(id -gn ${USER}) ${vault_dir_tls}

# Create a new certificate and save it to a file
vault write -format=json ${pki_path_intermediate}/issue/${pki_role_intermediate} \
  common_name="${ca_cert_file_name_vault_server}" >"${vault_dir_tls}/${ca_cert_file_name_vault_server}.crt"

# Extract the certificate, issuing ca in the pem file and private key in the key file seperately
cat ${vault_dir_tls}/${ca_cert_file_name_vault_server}.crt | jq -r .data.certificate >${vault_dir_tls}/${ca_cert_file_name_vault_server}.pem
cat ${vault_dir_tls}/${ca_cert_file_name_vault_server}.crt | jq -r .data.issuing_ca >>${vault_dir_tls}/${ca_cert_file_name_vault_server}.pem
cat ${vault_dir_tls}/${ca_cert_file_name_vault_server}.crt | jq -r .data.private_key >${vault_dir_tls}/${ca_key_file_name_vault_server}.key
