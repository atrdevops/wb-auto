#! /bin/bash

initfile=/var/tmp/wbauto.ini

LOGFILE="/var/tmp/wbauto_installation.log"


H_NAME="$(hostname | awk -F. '{print $1}')"

servertype="$(cat wbauto.ini |grep $H_NAME |awk -F= '{print $1}' |awk -F_ '{print $1}')"

echo """
server type is: $servertype

about to start installation. 

installation log file: $LOGFILE
"""

apt-get install curl -y
apt-get install -y software-properties-common # solve add-apt-repository command not found problem

useradd --no-create-home --shell /bin/false node_exporter

function exporter_conf () {

type=$1

type_release="$(cat $initfile |grep $type |awk -F= '{print $2}')"
echo "about to configure $type"

cd /root
curl -LO https://github.com/prometheus/$type/releases/download/v$type_release/$type-$type_release.linux-amd64.tar.gz ; wait
tar xvf $type-$type_release.linux-amd64.tar.gz ; wait
cp /root/$type-$type_release.linux-amd64/$type /usr/local/bin
chown node_exporter:node_exporter /usr/local/bin/$type
rm -rf $type

echo """[Unit]
Description=$type Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/$type

[Install]
WantedBy=multi-user.target
""" > /etc/systemd/system/$type.service

sed -i 's/scription=mysqld_exporter/scription=Mysqld/g' /etc/systemd/system/$type.service
sed -i 's/scription=node_exporter/scription=Node/g' /etc/systemd/system/$type.service


systemctl daemon-reload
systemctl enable $type
systemctl start $type

}

case $servertype in

  auth | wss)
    exporter_conf node_exporter
    ;;

  admin)
	apt-get install apache2 -y
    exporter_conf node_exporter
    ;;

  monitoring)
	p_release="$(cat $initfile |grep prometheus |awk -F= '{print $2}')"
    exporter_conf node_exporter
    ;;

  mysql)
    exporter_conf node_exporter
	exporter_conf mysqld_exporter
  
  redis)
    exporter_conf node_exporter

  freeswitch)
     exporter_conf node_exporter

  kamailio)
    exporter_conf node_exporter

  xmpp)
     exporter_conf node_exporter

  pfsense)
    echo -n "pfsense"
          

  *)
    echo -n "unknown server type. nothing done"
    ;;
esac

#
