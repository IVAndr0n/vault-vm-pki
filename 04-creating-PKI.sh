#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Name:           04-creating-PKI.sh
# Description:    We create our own certification authority in the Vault server
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

export VAULT_ADDR=http://${vault_server_fqdn}:8200
export VAULT_SKIP_VERIFY=true
export VAULT_NAMESPACE=${namespace_vault}
export ROOT_TOKEN=$(grep 'Initial Root Token:' ${vault_dir_config}/${vault_file_keys} | awk '{print $NF}')
export VAULT_TOKEN=${ROOT_TOKEN}

echo "We create directories and assign the necessary security rights"
sudo mkdir -pm 0755 ${vault_dir_crt}
sudo chown ${USER}:$(id -gn ${USER}) ${vault_dir_crt}

# 01_rootCA_generate
# Enable the pki secrets engine for root CA.
vault secrets enable \
  -path=${pki_path_root} \
  -description="${ca_common_name} Root CA" \
  -max-lease-ttl="${pki_ttl_root}" \
  pki

# Generate root CA, give it an issuer name, and save its certificate in the file *.crt.
vault write -field=certificate ${pki_path_root}/root/generate/internal \
  common_name="${ca_common_name} Root CA" \
  country="${ca_country}" \
  locality="${ca_locality}" \
  organization="${ca_organization}" \
  ou="${ca_ou}" \
  issuer_name="${pki_issuer_root}" \
  ttl="${pki_ttl_root}" >${vault_dir_crt}/${ca_cert_file_name_root}.crt

# Create a role for the root CA; creating this role allows for specifying an issuer when necessary for the purposes of this scenario.
# This also provides a simple way to transition from one issuer to another by referring to it by name.
vault write ${pki_path_root}/roles/${pki_role_root} allow_any_name=true

# Configure the CA and CRL URLs.
vault write ${pki_path_root}/config/urls \
  issuing_certificates="${VAULT_ADDR}/v1/${pki_path_root}/ca" \
  crl_distribution_points="${VAULT_ADDR}/v1/${pki_path_root}/crl"

# 02_intermediateCA_generate
# Enable the pki secrets engine for intermediate CA.
vault secrets enable \
  -path=${pki_path_intermediate} \
  -description="${ca_common_name} Intermediate CA" \
  -max-lease-ttl="${pki_ttl_intermediate}" \
  pki

# Execute the following command to generate an intermediate and save the CSR as *.csr.
vault write -format=json ${pki_path_intermediate}/intermediate/generate/internal \
  common_name="${ca_common_name} Intermediate CA" \
  country="${ca_country}" \
  locality="${ca_locality}" \
  organization="${ca_organization}" \
  ou="${ca_ou}" \
  issuer_name="${pki_issuer_intermediate}" | jq -r '.data.csr' >${vault_dir_crt}/pki_intermediate.csr

# Sign the intermediate certificate with the root CA private key, and save the generated certificate as *.pem.
vault write -format=json ${pki_path_root}/root/sign-intermediate \
  country="${ca_country}" \
  locality="${ca_locality}" \
  organization="${ca_organization}" \
  ou="${ca_ou}" \
  issuer_ref="${pki_issuer_root}" \
  csr=@${vault_dir_crt}/pki_intermediate.csr \
  format=pem_bundle \
  ttl="${pki_ttl_intermediate}" | jq -r '.data.certificate' >${vault_dir_crt}/${ca_cert_file_name_intermediate}.pem

# Once the CSR is signed and the root CA returns a certificate, it can be imported back into Vault.
vault write ${pki_path_intermediate}/intermediate/set-signed certificate=@${vault_dir_crt}/${ca_cert_file_name_intermediate}.pem

#--------------------------------------------
# Examine the output to the certificate file. Convert the root and int certs from .pem to .crt to be used in the Windows Certificate Store
#openssl x509 -text -noout -in ${vault_dir_crt}/${ca_cert_file_name_root}.crt
#openssl x509 -text -in ${vault_dir_crt}/${ca_cert_file_name_intermediate}.pem -out ${vault_dir_crt}/${ca_cert_file_name_intermediate}.crt
#openssl x509 -outform der -in ${vault_dir_crt}/${ca_cert_file_name_intermediate}.pem -out ${vault_dir_crt}/${ca_cert_file_name_intermediate}.crt
#--------------------------------------------

# Configure the CA and CRL URLs.
vault write ${pki_path_intermediate}/config/urls \
  issuing_certificates="${VAULT_ADDR}/v1/${pki_path_intermediate}/ca" \
  crl_distribution_points="${VAULT_ADDR}/v1/${pki_path_intermediate}/crl"

# 03_pki_int_create_role
# Create a role which allows subdomains, and specify the default issuer ref ID as the value of issuer_ref.
vault write ${pki_path_intermediate}/roles/${pki_role_intermediate} \
  country="${ca_country}" \
  locality="${ca_locality}" \
  organization="${ca_organization}" \
  ou="${ca_ou}" \
  issuer_ref="$(vault read -field=default ${pki_path_intermediate}/config/issuers)" \
  allowed_domains="${pki_allowed_domains}" \
  allow_subdomains=true \
  max_ttl="${pki_ttl_certificate}" \
  ttl="${pki_ttl_certificate}"

# 04_pki_int_policy
# Create policy to revoke updates and a list of certificates.
vault policy write "${pki_policy_intermediate}" - <<EOF
path "${pki_path_intermediate}/issue/*"         { capabilities = ["create", "update"] }
path "${pki_path_intermediate}/certs"           { capabilities = ["list"] }
path "${pki_path_intermediate}/revoke"          { capabilities = ["create", "update"] }
path "${pki_path_intermediate}/tidy"            { capabilities = ["create", "update"] }
path "${pki_path_root}/cert/ca"                 { capabilities = ["read"] }
path "auth/token/renew"                         { capabilities = ["update"] }
path "auth/token/renew-self"                    { capabilities = ["update"] }
EOF

# 05_userpass_create
# Enable the userpass auth method at userpass (for creating and managing the certificates).
vault auth enable -path="userpass" userpass

# Create a new user named ${pki_access_user_name} with password ${pki_access_user_name_password} with the policy we created earlier.
vault write auth/userpass/users/${pki_access_user_name} \
  password=${pki_access_user_name_password} \
  token_policies="${pki_policy_intermediate}"
