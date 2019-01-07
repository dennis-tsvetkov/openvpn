#!/bin/bash


sudo apt-get update
sudo apt-get install -y openvpn easy-rsa curl
make-cadir ~/openvpn-ca
cd ~/openvpn-ca

echo -e 'export KEY_NAME="server"' >> ./vars

source vars
./clean-all

# Build a root certificate
export EASY_RSA="${EASY_RSA:-.}"
"$EASY_RSA/pkitool" --initca

# Make a certificate/private key pair using a locally generated root certificate.
export EASY_RSA="${EASY_RSA:-.}"
"$EASY_RSA/pkitool" --server server

# generate a Diffie-Hellman keys 
./build-dh

openvpn --genkey --secret keys/ta.key



## client key pair
cd ~/openvpn-ca
source vars
# Make a certificate/private key pair using a locally generated root certificate.
export EASY_RSA="${EASY_RSA:-.}"
"$EASY_RSA/pkitool" client1

cd ~/openvpn-ca/keys
sudo cp ca.crt server.crt server.key ta.key dh2048.pem /etc/openvpn

gunzip -c /usr/share/doc/openvpn/examples/sample-config-files/server.conf.gz | sudo tee /etc/openvpn/server.conf

cat /etc/openvpn/server.conf | \
  sed "s/.*tls-auth *ta\.key.*//" | \
  sed "s/.*key-direction *0.*//" | \
  sed "s/.*cipher *AES-128-CBC.*//" | \
  sed "s/.*auth *SHA256.*//" | \
  sed "s/.*user *nobody.*//" | \
  sed "s/.*group *nogroup.*//" | \
  sed "s/.*route 10\.8\..*//" | \
  sed "s/.*redirect-gateway .*//" | \
  sed "s/[^#]*port .*//" | \
  sed "s/[^#]*proto .*//" | \
  sed "s/[^#]*cert .*//" | \
  sed "s/[^#]*key .*//" | \
  sudo tee /etc/openvpn/server.conf.new

echo -e "

tls-auth ta.key 0 # This file is secret
key-direction 0
cipher AES-128-CBC
auth SHA256

user nobody
group nogroup

push \"route 10.8.0.0 255.255.255.0\"
push \"redirect-gateway def1\"   # this will redirect all traffic into VPN server, disable it if it is not desired

# linkedin hosts
push \"route 104.225.0.0   255.255.0.0\"
push \"route 104.73.0.0   255.255.0.0\"
push \"route 108.174.0.0   255.255.0.0\"
push \"route 144.2.0.0   255.255.0.0\"
push \"route 152.195.0.0   255.255.0.0\"
push \"route 192.229.0.0   255.255.0.0\"
push \"route 35.241.0.0   255.255.0.0\"
push \"route 45.54.0.0   255.255.0.0\"
push \"route 69.192.0.0   255.255.0.0\"
push \"route 91.225.0.0   255.255.0.0\"
push \"route 95.100.0.0   255.255.0.0\"
push \"route 185.63.0.0   255.255.0.0\"

port 443
proto tcp

cert server.crt
key server.key
" | sudo tee -a /etc/openvpn/server.conf.new

sudo mv /etc/openvpn/server.conf.new   /etc/openvpn/server.conf


### enable forwarding in sysctl
cat /etc/sysctl.conf | sed "s/[^#]*net\.ipv4\.ip_forward.*//" | sudo tee /etc/sysctl.conf.new
echo -e "
net.ipv4.ip_forward=1
" | sudo tee -a /etc/sysctl.conf.new

sudo mv /etc/sysctl.conf.new   /etc/sysctl.conf
sudo sysctl -p

### enable NAT forwarding and make iptables rules persistent
sudo iptables -t nat -A POSTROUTING -o venet0 -j MASQUERADE
#sudo iptables -L -t nat     # to check the list of NAT rules
sudo apt-get install -y iptables-persistent



### fix LimitNPROC param
cat /lib/systemd/system/openvpn@.service | sed "s/.*\(LimitNPROC.*\)/#\1/" | sudo tee /lib/systemd/system/openvpn@.service.new
sudo mv /lib/systemd/system/openvpn@.service.new   /lib/systemd/system/openvpn@.service
systemctl daemon-reload

### start openvpn service
sudo systemctl restart openvpn@server
sudo systemctl enable openvpn@server


### Client Configuration
mkdir -p ~/client-configs/files
chmod 700 ~/client-configs/files
cp /usr/share/doc/openvpn/examples/sample-config-files/client.conf ~/client-configs/base.conf



EXT_IP=$(curl ifconfig.co)
echo "External IP of this server is $EXT_IP"
echo "Please, specify an address of the VPN server or hit Enter to keep it as $EXT_IP:"
read BUF
if [ "$BUF" == "" ];
then
    VPN_SERVER="$EXT_IP"
else
    VPN_SERVER=$BUF
fi
echo "VPN server is \"$VPN_SERVER\""


cat ~/client-configs/base.conf | \
  sed "s/[^#]*remote .*//" | \
  sed "s/[^#]*proto .*//" | \
  sed "s/[^#]*user .*//" | \
  sed "s/[^#]*group .*//" | \
  sed "s/[^#]*ca .*//" | \
  sed "s/[^#]*cert .*//" | \
  sed "s/[^#]*key .*//" | \
  sed "s/[^#]*cipher .*//" | \
  sed "s/[^#]*auth .*//" | \
  sed "s/[^#]*key-direction .*//" | \
  tee ~/client-configs/base.conf.new

echo -e "
remote $VPN_SERVER 443
proto tcp
user nobody
group nogroup
ca ca.crt
cert client.crt
key client.key
cipher AES-128-CBC
auth SHA256
key-direction 1
"  | tee -a ~/client-configs/base.conf.new

mv ~/client-configs/base.conf.new   ~/client-configs/base.conf  
 

### create  ~/client-configs/make_config.sh

echo -e "
#!/bin/bash

# First argument: Client identifier

KEY_DIR=~/openvpn-ca/keys
OUTPUT_DIR=~/client-configs/files
BASE_CONFIG=~/client-configs/base.conf

cat \${BASE_CONFIG} \\
    <(echo -e '<ca>') \\
    \${KEY_DIR}/ca.crt \\
    <(echo -e '</ca>\\n<cert>') \\
    \${KEY_DIR}/\${1}.crt \\
    <(echo -e '</cert>\\n<key>') \\
    \${KEY_DIR}/\${1}.key \\
    <(echo -e '</key>\\n<tls-auth>') \\
    \${KEY_DIR}/ta.key \\
    <(echo -e '</tls-auth>') \\
    > \${OUTPUT_DIR}/\$1.ovpn
" > ~/client-configs/make_config.sh

chmod 700 ~/client-configs/make_config.sh

cd ~/client-configs

echo "execute this to check the status of openvpn service:     sudo systemctl status openvpn@server"
echo "now you can generate client configs with the following command:    cd ~/client-configs && ./make_config.sh <client-name>"
