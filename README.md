# setting_up_provider


## Install Required Dependencies, Generate Certificate and Add an Nginx Config for Each Domain
You can do this using a **script** or **manually**.

### Script
```
./gependencies_certificate_nginx-config.sh
```

### 📂 Install Required Dependencies

First, set up and configure Nginx to use a TLS certificate and handle connections. You can use alternatives like Caddy or Envoy if preferred.

Run the following commands to install the necessary packages:
```
sudo apt update
sudo apt install certbot net-tools nginx python3-certbot-nginx -y
```

### 📮 Generate Certificate

Next, create the TLS certificate with certbot:
```
sudo certbot certonly --nginx -d you.xyz -d lava.you.xyz -d eth.you.xyz
```
Ensure you use a -d flag for each subdomain you created as an A-Record. Follow the prompts and choose the Nginx plugin when asked.

### 💻 Validate Certificate

Verify your certificate installation:
```
sudo certbot certificates
```
A successful output should look like this:
```
Found the following certs:
  Certificate Name: your-site.com
    Domains: your-site.com eth.your-site.com lava.your-site.com
    Expiry Date: YYYY-MM-DD HH:MM:SS+00:00 (VALID: XX days)
    Certificate Path: /etc/letsencrypt/live/your-site.com/fullchain.pem
    Private Key Path: /etc/letsencrypt/live/your-site.com/privkey.pem
```
You’ll need the Certificate Path and Private Key Path for the next step.

### 🗃️ Add an Nginx Config for Each Domain

For each chain you want to support, create a separate Nginx config file. This ensures separation of error logs and isolates issues.

Navigate to /etc/nginx/sites-available/ and create a config file for each chain. Use an open port for each.

Example for eth_server:
```
sudo nano /etc/nginx/sites-available/lava-provider_server
```
```
server {
    listen 443 ssl http2;
    server_name lava-provider.your-site.com;

    ssl_certificate /etc/letsencrypt/live/lava-provider.your-site.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/lava-provider.your-site.com/privkey.pem;
    error_log /var/log/nginx/debug.log debug;

    location / {
        proxy_pass http://127.0.0.1:2223;
        grpc_pass 127.0.0.1:2223;
    }
}
```
### ⚠️ Caution

Ensure you use port 443 for external listening to avoid connectivity issues. Avoid internal ports used by the OS.

### 🧪 Test Nginx Configuration

Check your Nginx setup:
```
sudo nginx -t
```
Expected Output:
```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

### ♻️ Restart Nginx

Restart the Nginx server:
```
sudo systemctl restart nginx
```

## Create the Provider Configuration

### ⚙️ Create the Provider Configuration

TIP: Need a template? A default rpcprovider.yml configuration is available in ~/lava/config.

We’ll create one .yml file per chain we plan to support. For this example, we’ll create lava-provider.yml and eth-provider.yml.

Example for lava-provider.yml:
```
endpoints:
  - api-interface: tendermintrpc
    chain-id: LAV1
    network-address:
      address: 127.0.0.1:2224
      disable-tls: true
    node-urls:
      - url: ws://127.0.0.1:26657/websocket
      - url: http://127.0.0.1:26657
  - api-interface: grpc
    chain-id: LAV1
    network-address:
      address: 127.0.0.1:2224
      disable-tls: true
    node-urls:
      - url: 127.0.0.1:9090
  - api-interface: rest
    chain-id: LAV1
    network-address:
      address: 127.0.0.1:2224
      disable-tls: true
    node-urls:
      - url: http://127.0.0.1:1317
```
Once these files are created, you can start the provider processes.

## Start the Provider Process, Test the Provider Process, Stake the Provider on Chain and Test the Providers again!


### 🏁 Start the Provider Process(es)

First we need to set the following values:
```
TMP_PASSWORD=<your wallet password if you have one>
TMP_CONFIG_FILE_PATH=<path to your config file>
TMP_GEO_LOCATION=<the geolocation you wish to use>
TMP_PROVIDER_WALLET_ACCOUNT=<your provider wallet account name>
TMP_CHAIN_ID=<the lava chain id to run this on> # lava-testnet-2
```
Run the following to create the service file:
```
sudo tee <<EOF >/dev/null /etc/systemd/system/lava-provider.service
[Unit]
Description=Lava Provider
After=network-online.target
[Service]
# the user that runs the service
User=root

# set the working directory so that its easier to note the config file
WorkingDirectory=/root

# since we are using the wallet we must send in the password automatically
ExecStart=/usr/bin/sh -c 'echo $TMP_PASSWORD | /usr/bin/lavap rpcprovider $TMP_CONFIG_FILE_PATH --geolocation $TMP_GEO_LOCATION --from $TMP_PROVIDER_WALLET_ACCOUNT --chain-id $TMP_CHAIN_ID'

Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
```
Finally enable and run the service:
```
sudo systemctl daemon-reload
sudo systemctl enable lava-provider.service
sudo systemctl start lava-provider.service
```
View the logs:
```
journalctl -fn 1000 -u lava-provider.service -o cat
```


### ☑️ Test the Provider Process!

Run the following commands one at a time:
```
lavap test rpcprovider --from your_key_name_here --endpoints "your-site:443,LAV1"
```
Expected output:
```
📄----------------------------------------✨SUMMARY✨----------------------------------------📄

🔵 Tests Passed:
🔹LAV1-grpc latest block: 0x4ca8c
🔹LAV1-rest latest block: 0x4ca8c
🔹LAV1-tendermintrpc latest block: 0x4ca8c

🔵 Tests Failed:
🔹None 🎉! all tests passed ✅

🔵 Provider Port Validation:
🔹✅ All Ports are valid! ✅
```

🔗 Stake the Provider on Chain
Stake on chain with the following command (minimum stake is 50000000000ulava):
```
lavap tx pairing stake-provider LAV1 "50000000000ulava" "lava.your-site:443,1" 1 validator_addr -y --from your_key_name_here --provider-moniker your-provider-moniker-1 --delegate-limit "0ulava" --gas-adjustment "1.5" --gas "auto" --gas-prices "0.0001ulava"
```

### ☑️ Test the Providers again!
```
lavap q pairing account-info --from your_key_name
```
