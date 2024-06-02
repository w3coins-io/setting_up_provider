#!/bin/bash
FILE_PATH=$HOME
PORT=""
URL_CHAINS_PROVIDER="https://public-rpc-testnet2.lavanet.xyz/rest/lavanet/lava/spec/show_all_chains"

# Function to print info messages in blue
print_info2() {
  echo -e "\e[1;34m$1\e[0m"
}

# Function to print error messages in red
print_error() {
  echo -e "\e[1;31m$1\e[0m"
}

# Function to print info messages in yellow
print_info() {
  echo -e "\e[1;33m$1\e[0m"
}

# Function to check if a port is in use
check_port() {
  if sudo lsof -i -P -n | grep -q ":$1"; then
    return 1
  else
    return 0
  fi
}

# Function to generate SSL certificates with retries on failure
generate_certificates() {
  while true; do
    sudo certbot certonly --nginx -d $subdomain.$main_domain
    output=$(sudo certbot certonly --nginx -d $subdomain.$main_domain )
    echo $output
    output=$(sudo certbot certonly --nginx -d $subdomain.$main_domain 2>&1)
    print_info "$output"
    if "$output" == *"failed"* | "$output" == "error"; then
      break
    else
      print_error "SSL certificate creation failed."
      exit 0;
    fi
  done
}

confirm_execution() {
  while true; do
    read -p "$1 (Yes/no/quit): " yn
    case $yn in
      [Yy]* | "") return 0;;
      [Nn]* ) return 1;;
      [Qq]* ) echo "Quitting script."; exit 0;;
      * ) echo "Please answer yes, no or quit.";;
    esac
  done
}



print_info "📂 Install Required Dependencies"
sudo apt update
sudo apt install certbot net-tools nginx python3-certbot-nginx -y
print_info "OPEN PORT 80 443"
sudo ufw allow 80
sudo ufw allow 443


print_info2 "###############################################"
print_info  "             NGINX CONFIGURATION               "
print_info2 "###############################################\n"


read -p "Enter your main domain (e.g., you.xyz): " main_domain
read -p "Enter subdomains (comma separated, e.g., lava.you.xyz,eth.you.xyz): " subdomains
IFS=',' read -ra ADDR <<< "$subdomains"

if confirm_execution "Do you want to generate SSL certificates?"; then

print_info "📮 Generate Certificate"

# Convert comma-separated subdomains to certbot -d flags
for subdomain in "${ADDR[@]}"; do
  #certbot_domains+=" -d $subdomain.$main_domain"
  echo "sudo certbot certonly --nginx $subdomain.$main_domain"
  sudo certbot certonly --nginx -d $subdomain.$main_domain
done
fi

print_info "💻 Validate Certificate"
sudo certbot certificates


if confirm_execution "Do you want to add an Nginx config for each domain?"; then
print_info "🗃️ Add an Nginx Config for Each Domain "
# Create Nginx config files for each subdomain

for subdomain in "${ADDR[@]}"; do
  subdomain_prefix="${subdomain%%.*}"  # Extract the part before the first dot
  while true; do
    read -p "Enter the port for this subdomain ($subdomain_prefix): " port
    if check_port $port; then
      break
    else
      print_error "Port $port is already in use. Please enter a different port."
    fi
  done

  config_file="/etc/nginx/sites-enabled/${subdomain_prefix}_server"
  sudo bash -c "cat > $config_file <<EOF
server {
    listen 443 ssl http2;
    server_name $subdomain.$main_domain;

    ssl_certificate /etc/letsencrypt/live/$subdomain.$main_domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$subdomain.$main_domain/privkey.pem;
    error_log /var/log/nginx/debug.log debug;

    location / {
        proxy_pass http://127.0.0.1:$port;
        grpc_pass 127.0.0.1:$port;
    }
}
EOF"

  print_info "Created configuration file: $config_file"
done

fi

print_info "🧪 Test Nginx Configuration"
sudo nginx -t

print_info "♻️ Restart Nginx"
sudo systemctl restart nginx

print_info "✅ Setup Complete!"

print_info "⚠️  If you did not receive the results “syntax is ok” and “test is successful,” we recommend addressing these issues first before proceeding further with the script."




print_info2 "###############################################"
print_info  "                CREATING A YML                 "
print_info  "              CONFIGURATION FILE               "
print_info2 "###############################################\n"

if confirm_execution "Do you want to create ${name_file}.yml file?"; then

# Check for the presence of jq
if ! command -v jq &> /dev/null
then
    print_info "Installing jq..."
    sudo apt-get install jq
fi


# Prompt for the directory where the files will be created
read -p "Enter the directory path to create the files (default is $FILE_PATH): " file_path
FILE_PATH=${file_path:-$HOME}

if [ -d "$FILE_PATH" ]; then
    echo "The specified directory exists:" && print_info2 "$FILE_PATH"
else
    print_error "Directory not found: $FILE_PATH"
    read -p "Do you want to create this directory? (y/n): " create_folder
    if [[ $create_folder == [Yy] ]]; then
        mkdir -p "$FILE_PATH"
        if [ $? -eq 0 ]; then
            print_info2 "Directory successfully created: $FILE_PATH"
        else
            print_error "Failed to create the directory."
        fi
    else
        print_error "Directory not created."
        exit 0;
    fi
fi

# Reading the chains.json file
chains_json=$(curl -s $URL_CHAINS_PROVIDER)


# Getting the list of networks
echo "Available networks:"
networks=$(echo "$chains_json" | jq -r '.chainInfoList[] | "\(.chainName) -> \(.chainID)"')

IFS=$'\n' read -d '' -r -a networks_array <<< "$networks"

for i in "${!networks_array[@]}"; do
  echo "$(( i + 1 )): ${networks_array[$i]}"
done

while true; do
# Prompt to select a network
read -p "Choose the network index: " network_index
network_index=$((network_index - 1))

if ! [[ $network_index =~ ^[0-9]+$ ]] || [ "$network_index" -ge "${#networks_array[@]}" ]; then
  echo "Invalid network selection."
  exit 1
fi

selected_network=$(echo "${networks_array[$network_index]}")
chain_name=$(echo "$selected_network" | cut -d' ' -f1)
file_name=$chain_name-$(echo "$selected_network" | cut -d' ' -f2)
chain_id=$(echo "$selected_network" | awk -F' -> ' '{print $2}')

echo "Selected network: $chain_name ($chain_id)"
echo $file_name

# Retrieving API interfaces for the selected network
api_interfaces=$(echo "$chains_json" | jq -r ".chainInfoList[] | select(.chainID == \"$chain_id\") | .enabledApiInterfaces[]")

# Creating the YAML file
output_file="$FILE_PATH/$file_name.yml"
echo "endpoints:" > "$output_file"

IFS=$'\n' read -d '' -r -a api_interfaces_array <<< "$api_interfaces"

read -p "Enter the port for $chain_name (this port you entered in the nginx configuration): " port
for interface in "${api_interfaces_array[@]}"; do
  if [ "$interface" == "grpc" ]; then
    read -p "Enter URLs for $interface (e.g., lava-grpc.w3coins.io:9090): " node_urls
  elif [ "$interface" == "tendermintrpc" ]; then
    read -p "Enter URLs for $interface (e.g., https://lava-rpc.w3coins.io:443): " node_urls
  elif [ "$interface" == "jsonrpc" ]; then
    read -p "Enter URLs for $interface (e.g., https://lava-jsonrpc.w3coins.io:443): " node_urls
  elif [ "$interface" == "rest" ]; then
    read -p "Enter URLs for $interface (e.g., https://lava-rest.w3coins.io:443): " node_urls
  else
    read -p "Enter URLs for $interface: " node_urls
  fi

  echo "  - api-interface: $interface" >> "$output_file"
  echo "    chain-id: $chain_id" >> "$output_file"
  echo "    network-address:" >> "$output_file"
  echo "      address: \"127.0.0.1:$port\"" >> "$output_file"
  echo "      disable-tls: true" >> "$output_file"
  echo "    node-urls:" >> "$output_file"
  echo "      - url: $node_urls" >> "$output_file"
done

echo "File created at: $output_file"

read -p "Do you want to create configuration file for new provider again? (y/n): " config_file_p
  if [[ $config_file_p == [Yy] ]]; then
    continue
  else
    break
  fi
done
fi

print_info2 "###############################################"
print_info  "                 CREATING                      "
print_info  "               SERVICE FILE                    "
print_info2 "###############################################\n"

if confirm_execution "Do you want to create service file?"; then

while true; do
read -p "Enter your wallet password: " TMP_PASSWORD
read -p "Enter the path to your config file ($FILE_PATH): " TMP_CONFIG_FILE_PATH
FILE_PATH=${TMP_CONFIG_FILE_PATH:- $FILE_PATH}

configuration_providers=( $( cd $FILE_PATH && ls *.yml ) )

print_info "Select configuration providers to create the service file:"
select config_file in "${configuration_providers[@]}"; do
  if [ -n "$config_file" ]; then
    print_info "You select $config_file"
    break
  else
   print_error "Invalid configuration providers selection."
  fi
done

read -p "Enter the geolocation you use (USC = 1; EU = 2; more info https://docs.lavanet.xyz/provider-setup#step-4-stake-as-provider): " TMP_GEO_LOCATION
read -p "Enter your provider wallet account name: " TMP_PROVIDER_WALLET_ACCOUNT
read -p "Enter the Lava chain ID to run this on (e.g., defaut lava-mainnet-1): " TMP_CHAIN_ID
TMP_CHAIN_ID=${TMP_CHAIN_ID:- "lava-mainnet-1"}

service_name=$(echo "$config_file" | cut -d'.' -f1)

# Create the systemd service file
echo "Creating the systemd service file for Lava Provider..."
sudo tee /etc/systemd/system/$service_name-provider.service > /dev/null <<EOF
[Unit]
Description=Lava Provider
After=network-online.target

[Service]
# The user that runs the service
User=$USER

# Set the working directory so that it's easier to note the config file
WorkingDirectory=$FILE_PATH

# Since we are using the wallet, we must send in the password automatically
ExecStart=/usr/bin/sh -c "echo '$TMP_PASSWORD' | $(which lavap) rpcprovider $config_file --geolocation $TMP_GEO_LOCATION --from $TMP_PROVIDER_WALLET_ACCOUNT --chain-id $TMP_CHAIN_ID"

Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
echo "Create file at: "
print_info2 "/etc/systemd/system/$service_name-provider.service"

# Reload systemd, enable and start the service
echo "Reloading systemd daemon and enabling the service"
sudo systemctl daemon-reload
sudo systemctl enable $service_name-provider.service
#sudo systemctl start $service_name-provider.service

echo "You can start the service with this command: "
print_info "systemctl start $service_name-provider.service"
echo "To view the logs, run: "
print_info "journalctl -fn 1000 -u $service_name-provider.service -o cat"

read -p "Do you want to create service file for new provider again? (y/n): " service_file_p
  if [[ $service_file_p == [Yy] ]]; then
    continue
  else
    break
  fi

done
fi


print_info2 "###############################################"
print_info  "               End of script                   "
print_info2 "###############################################\n"
