#!/bin/bash
#----------------------------
#  add user to vpn
#----------------------------

cd /etc/openvpn/easy-rsa
source vars

echo -n "User name:"
read USER

echo -n "Specify external address of the VPN server, clients should connect to:"
read SERVER

./pkitool --pass $USER

echo "
client
dev tun
proto udp
resolv-retry infinite
nobind
user nobody
group nogroup
persist-key
persist-tun
ns-cert-type server
comp-lzo
verb 3
remote $SERVER 1194
" > keys/$USER.ovpn

echo '<ca>' >> keys/$USER.ovpn
cat keys/ca.crt >> keys/$USER.ovpn
echo '</ca>' >> keys/$USER.ovpn

echo '<cert>' >> keys/$USER.ovpn
cat keys/$USER.crt >> keys/$USER.ovpn
echo '</cert>' >> keys/$USER.ovpn

echo '<key>' >> keys/$USER.ovpn
cat keys/$USER.key >> keys/$USER.ovpn
echo '</key>' >> keys/$USER.ovpn

echo "Done! Client profile is available here: /etc/openvpn/easy-rsa/keys/$USER.ovpn"
