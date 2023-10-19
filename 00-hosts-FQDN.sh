#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Name:           00-hosts-FQDN.sh
# Description:    Additional FQDN binding to all IP addresses in the hosts file
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

# Get a list of all local IP addresses in the system
ip_addresses=($(hostname -I))

# Trying to execute commands with sudo
sudo -n true 2>/dev/null

# Check if sudo succeeded
if [ $? -ne 0 ]; then
    echo -e "\e[33mThe script requires administrator rights. Please enter a password for sudo.\e[0m"
    sudo -v

    # At this point, the script will wait for the sudo password to be entered
    # After entering the password, it will continue executing with administrator privileges

    if [ $? -ne 0 ]; then
        echo -e "\e[31mSudo authentication failed. Script Exit.\e[0m"
        exit 1
    fi
fi

# If we got to this point, then sudo is successful
if [ ${#ip_addresses[@]} -gt 0 ]; then
    # Delete all previous entries for our FQDN in the hosts file
    sudo sed -i "/${vault_server_fqdn}/d" ${hosts_file}
    # Add FQDN binding to all IP addresses in the hosts file (temporarily until the DNS server is configured)
    for ip in "${ip_addresses[@]}"; do
        echo "${ip} ${vault_server_fqdn}" | sudo tee -a ${hosts_file}
        echo -e "\e[32mThe found IP address was added to the ${hosts_file} file.\e[0m"
    done
else
    echo -e "\e[31mFailed to determine current IP addresses.\e[0m"
fi
