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


function check_status () {
service1=$1
service_state="$(systemctl status $service1 |grep Active |awk '{print $2}')"
if [ "$service_state" == "active" ]; then
	echo """ ########################################
$service1 service is running
########################################
"""
else 
	echo """ ########################################
$service1 service is not running!!
check manually after installation
########################################
"""
}

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
systemctl start $type ; wait
check_status $type

if [ "$(systemctl status $type |grep Active |awk -F: '{print $2}' |awk '{print $1}')" == "active" ]; then
	echo "service $type is up and running"
else
	echo "$type is configured but doesn't start. please check" >> LOGFILE
fi

}

function check_status () {
service1=$1
service_state="$(systemctl status $service1 |grep Active |awk '{print $2}')"
if [ "$service_state" == "active" ]; then
	echo """ ########################################
$service1 service is running
########################################
"""
else 
	echo """ ########################################
$service1 service is not running!!
check manually after installation
########################################
"""
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
		s_ip="$(cat $initfile |grep $stype |grep ip |grep -v data |awk -F= '{print $2}')"
		sed -i "s/$stype:/$s_ip:/g" /etc/prometheus/prometheus.yml
	done
		
		
	systemctl daemon-reload
	systemctl enable prometheus
	systemctl start prometheus; wait
	check_status prometheus

	
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
	systemctl enable redis
	systemctl restart redis; wait
	check_status redis

    exporter_conf node_exporter
	exporter_conf redis_exporter
    ;;

  freeswitch)
	apt-get update && apt-get install -y gnupg2 wget ; wait
	wget -O - https://files.freeswitch.org/repo/deb/freeswitch-1.8/fsstretch-archive-keyring.asc | apt-key add - ; wait
	echo "deb http://files.freeswitch.org/repo/deb/freeswitch-1.8/ stretch main" > /etc/apt/sources.list.d/freeswitch.list
	apt-get update && apt-get install -y freeswitch-meta-all ; wait
	
    exporter_conf node_exporter
    ;;

  kamailio)
    exporter_conf node_exporter
	echo "installaing kamailio server"
	echo "deb http://deb.kamailio.org/kamailio51 stretch main" > /etc/apt/sources.list.d/kamailio.list
	wget -O- http://deb.kamailio.org/kamailiodebkey.gpg | apt-key add -
	apt-get update
	apt-get install -y net-tools procps kamailio kamailio-mysql-modules kamailio-tls-modules kamailio-xml-modules gnupg wget
	
	echo "installing rtpengine"
	
	apt-get install -y dpkg-dev
	apt-get install -y git
	git clone https://github.com/sipwise/rtpengine.git /root/rtpengine
	
	cd /root/rtpengine<<EOF
	apt-get install debhelper default-libmysqlclient-dev gperf iptables-dev libavcodec-dev libavfilter-dev libavformat-dev\
	libavutil-dev libbencode-perl libcrypt-openssl-rsa-perl libcrypt-rijndael-perl libhiredis-dev libio-multiplex-perl libio-socket-inet6-perl\
	libjson-glib-dev libdigest-crc-perl libdigest-hmac-perl libnet-interface-perl libnet-interface-perl libssl-dev libsystemd-dev\
	libxmlrpc-core-c3-dev libcurl4-openssl-dev libevent-dev libpcap0.8-dev markdown unzip nfs-common -y ; wait
	
	VER=1.0.4
	curl https://codeload.github.com/BelledonneCommunications/bcg729/tar.gz/$VER >bcg729_$VER.orig.tar.gz
	tar zxf bcg729_$VER.orig.tar.gz 
	cd bcg729-1.0.4
	git clone https://github.com/ossobv/bcg729-deb.git debian ; wait
	dpkg-buildpackage -us -uc -sa
	cd ../
	dpkg -i libbcg729-*.deb
	
	cd /root/rtpengine
	dpkg-buildpackage ; wait
	cd ../
	dpkg -i ngcp-rtpengine-daemon_*.deb ngcp-rtpengine-iptables_*.deb ; wait
	apt-get install -y dkms
	dpkg -i ngcp-rtpengine-kernel-dkms_*.deb ; wait

	mv /etc/rtpengine/rtpengine.sample.conf /etc/rtpengine/rtpengine.conf
	sed -i 's/# interface = internal/interface = internal/g' /etc/rtpengine/rtpengine.conf
	mgmtip=cat $initfile |grep kamailio |grep ip |grep -v data |awk -F= '{print $2}'
	dataip=cat $initfile |grep kamailio |grep ip |grep data |awk -F= '{print $2}'
	sed -i 's/12.23.34.45/$dataip/g' /etc/rtpengine/rtpengine.conf
	sed -i 's/23.34.45.54/$mgmtip/g' /etc/rtpengine/rtpengine.conf
	systemctl start ngcp-rtpengine-daemon
	dpkg -i ngcp-rtpengine-daemon-dbgsym_7.3.0.0+0~mr7.3.0.0_amd64.deb
	dpkg -i ngcp-rtpengine-utils_7.3.0.0+0~mr7.3.0.0_all.deb
	apt-get install module-assistant -y
	dpkg -i ngcp-rtpengine-kernel-source_7.3.0.0+0~mr7.3.0.0_all.deb
	sed -i 's/RUN_RTPENGINE=no/RUN_RTPENGINE=yes/g' /etc/default/ngcp-rtpengine-daemon	
EOF
	
	systemctl restart ngcp-rtpengine-daemon
	systemctl enable ngcp-rtpengine-daemon
	check_status systemctl ngcp-rtpengine-daemon
				
    ;;

  xmpp)
	ejurl="$(cat /var/tmp/wbauto.ini |grep url | sed 's/ejabberd_download_url=//g')"
	echo "ejabberd installation file url: $ejurl"
	wget $ejurl ; wait
	mv *ejabberd*.deb ejabberd_pkg.deb
	dpkg -i ejabberd_pkg.deb ;  wait
	cp /opt/ejabberd-*/bin/ejabberd.service /etc/systemd/system/
	systemctl daemon-reload
	systemctl enable ejabberd
	systemctl start ejabberd; wait
	check_status ejabberd
	 
	echo "alias ejabberdctl="/opt/ejabberd-*/bin/ejabberdctl"" >> ~/.profile
	source ~/.profile
 
    exporter_conf node_exporter
    ;;
 
  *)
    echo -n "unknown server type. nothing done" ; 
    ;;
esac

echo "script ended. exiting."

#eof

