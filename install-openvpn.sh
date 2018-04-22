#!/bin/bash
export SUBNET="10.8.3.0 255.255.255.0"

apt-get install -y openvpn easy-rsa openssl sed 

mkdir -p /etc/openvpn/easy-rsa/keys
cp -R /usr/share/easy-rsa/  /etc/openvpn

gunzip /usr/share/doc/openvpn/examples/sample-config-files/server.conf.gz -c | \
  sed "s/dh dh[0-9]*.pem/dh dh2048.pem/" | \
  sed "s/server 10\.8.*/server $SUBNET/" > /etc/openvpn/server.conf 

cd /etc/openvpn/easy-rsa
cp openssl-1.0.0.cnf openssl.cnf
source vars
./clean-all
./build-dh
./pkitool --initca
./pkitool --server server
cd keys
openvpn --genkey --secret ta.key
cp /etc/openvpn/easy-rsa/keys/{server.crt,server.key,ca.crt,dh2048.pem,ta.key} /etc/openvpn
service openvpn restart
echo "DONE! Reboot is needed."

