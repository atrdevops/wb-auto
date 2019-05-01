#! /bin/bash

initfile=/var/tmp/wbauto.ini

if [ ! -f $initfile ]; then
	echo "there is no wbauto.ini file under /var/tmp/ . exiting... "
	exit 1
fi


touch $LOGFILE

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

useradd --no-create-home --shell /bin/false $type

type_release="$(cat $initfile |grep $type |awk -F= '{print $2}')"
echo "about to configure $type"

cd /root
curl -LO https://github.com/prometheus/$type/releases/download/v$type_release/$type-$type_release.linux-amd64.tar.gz ; wait
tar xvf $type-$type_release.linux-amd64.tar.gz ; wait
cp /root/$type-$type_release.linux-amd64/$type /usr/local/bin
chown $type:$type /usr/local/bin/$type
rm -rf $type

echo """[Unit]
Description=$type Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=$type
Group=$type
Type=simple
ExecStart=/usr/local/bin/$type

[Install]
WantedBy=multi-user.target
""" > /etc/systemd/system/$type.service

sed -i 's/scription=mysqld_exporter/scription=Mysqld/g' /etc/systemd/system/$type.service
sed -i 's/scription=node_exporter/scription=Node/g' /etc/systemd/system/$type.service
sed -i 's/scription=redis_exporter/scription=Redis/g' /etc/systemd/system/$type.service


systemctl daemon-reload
systemctl enable $type
systemctl start $type

if [ "$(systemctl status $type |grep Active |awk -F: '{print $2}' |awk '{print $1}')" == "active" ]; then
	echo "service $type is up and running"
else
	echo "$type is configured but doesn't start. please check" >> LOGFILE
fi

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
	if [ ! -f /var/tmp/prometheus.yml ]; then
		echo "prometheus.yml file is missing from: /var/tmp/. nothing done. exiting script"
		exit 1
	fi
	p_release="$(cat $initfile |grep prometheus |awk -F= '{print $2}')"
	useradd --no-create-home --shell /bin/false prometheus
	mkdir /etc/prometheus
	mkdir /var/lib/prometheus
	cd /root
	curl -LO https://github.com/prometheus/prometheus/releases/download/v$p_release/prometheus-$p_release.linux-amd64.tar.gz
	tar xvf prometheus-$p_release.linux-amd64.tar.gz
	cp prometheus-$p_release.linux-amd64/prometheus /usr/local/bin/
	cp prometheus-$p_release.linux-amd64/promtool /usr/local/bin
	chown prometheus:prometheus /usr/local/bin/prometheus
	chown prometheus:prometheus /usr/local/bin/promtool
	cp -r prometheus-$p_release.linux-amd64/consoles /etc/prometheus
	cp -r prometheus-$p_release.linux-amd64/console_libraries /etc/prometheus
	chown -R prometheus:prometheus /etc/prometheus
	rm -rf prometheus-$p_release.linux-amd64.tar.gz prometheus-$p_release.linux-amd64
	echo """[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file /etc/prometheus/prometheus.yml \
    --storage.tsdb.path /var/lib/prometheus/ \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries

[Install]
WantedBy=multi-user.target""" > /etc/systemd/system/prometheus.service

	
	cp /var/tmp/prometheus.yml /etc/prometheus/
	
	for stype in admin auth wss monitoring mysql redis freeswitch kamailio xmpp; do 
		s_ip="$(cat $initfile |grep $stype |grep ip |awk -F= '{print $2}')"
		sed -i "s/$stype:/$s_ip:/g" /etc/prometheus/prometheus.yml
	done
		
		
	systemctl daemon-reload
	systemctl enable prometheus
	systemctl start prometheus

	
	g_release="$(cat $initfile |grep grafana_release | awk -F= '{print $2}')"
	
	wget https://dl.grafana.com/oss/release/grafana_$g_release_amd64.deb ; wait
	sudo dpkg -i grafana_$g_release_amd64.deb 
	
	
	
    exporter_conf node_exporter
    ;;

  mysql)
    exporter_conf node_exporter
	exporter_conf mysqld_exporter
    ;;
  
  redis)
	apt update
	apt install redis-server -y
	sed -i 's/supervised no/supervised systemd/g' /etc/redis/redis.conf
	sed -i 's/#   supervised systemd/#   supervised no/g' /etc/redis/redis.conf
	systemctl restart redis

    exporter_conf node_exporter
	exporter_conf redis_exporter
    ;;

  freeswitch)
     exporter_conf node_exporter
    ;;

  kamailio)
    exporter_conf node_exporter
    ;;

  xmpp)
	 ej_release="$(cat $initfile |grep ejabberd |awk -F= '{print $2}')"
     exporter_conf node_exporter
    ;;

  pfsense)
    echo -n "pfsense"
    ;;
          

  *)
    echo -n "unknown server type. nothing done" ; 
    ;;
esac

echo "script ended. exiting."

#eof


