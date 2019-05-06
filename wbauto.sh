#! /bin/bash

initfile=/var/tmp/wbauto.ini

if [ ! -f $initfile ]; then
	echo "there is no wbauto.ini file under /var/tmp/ . exiting... "
	exit 1
fi

H_NAME="$(hostname | awk -F. '{print $1}')"

servertype="$(cat $initfile |grep $H_NAME |awk -F= '{print $1}' |grep -v ip |awk -F_ '{print $1}')"

echo """
server type is: $servertype
about to start installation. 
installation log file: $LOGFILE
"""

apt-get install curl -y 
apt-get install -y software-properties-common # solve add-apt-repository command not found problem
apt-get install -y expect

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
fi
}

function exporter_conf () {

type=$1

useradd --no-create-home --shell /bin/false $type

type_release="$(cat $initfile |grep $type |awk -F= '{print $2}')"
echo "about to configure $type"

cd /root

if [ "$type" == "redis_exporter" ]; then
	curl -LO https://github.com/oliver006/redis_exporter/releases/download/v$type_release/redis_exporter-v$type_release.linux-amd64.tar.gz ; wait
	tar redis_exporter-v$type_release.linux-amd64.tar.gz ; wait
		cp /root/redis_exporter /usr/local/bin
else
		curl -LO https://github.com/prometheus/$type/releases/download/v$type_release/$type-$type_release.linux-amd64.tar.gz ; wait
		tar xvf $type-$type_release.linux-amd64.tar.gz ; wait
		cp /root/$type-$type_release.linux-amd64/$type /usr/local/bin
fi
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


if [[ ( "$servertype" == "auth" ) || ( "$servertype" == "wss" ) ]] ; then
    apt install default-jre -y
    apt install default-jdk -y
    exporter_conf node_exporter
fi

if [ "$servertype" == "admin" ]; then
	apt-get install apache2 -y
    exporter_conf node_exporter
fi

if [ "$servertype" == "monitoring" ]; then
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
	
	wget https://dl.grafana.com/oss/release/grafana_"$g_release"_amd64.deb ; wait
	sudo dpkg -i grafana_"$g_release"_amd64.deb 
	check_status grafana-server
	
	
	
    exporter_conf node_exporter
fi

if [ "$servertype" == "mysql" ]; then
    exporter_conf node_exporter
	exporter_conf mysqld_exporter
fi
  
if [ "$servertype" == "redis" ]; then
	apt update
	apt install redis-server -y
	sed -i 's/supervised no/supervised systemd/g' /etc/redis/redis.conf
	sed -i 's/#   supervised systemd/#   supervised no/g' /etc/redis/redis.conf
	systemctl enable redis
	systemctl restart redis; wait
	check_status redis

    exporter_conf node_exporter
	exporter_conf redis_exporter
fi

if [ "$servertype" == "freeswitch" ]; then
	apt-get update && apt-get install -y gnupg2 wget ; wait
	wget -O - https://files.freeswitch.org/repo/deb/freeswitch-1.8/fsstretch-archive-keyring.asc | apt-key add - ; wait
	echo "deb http://files.freeswitch.org/repo/deb/freeswitch-1.8/ stretch main" > /etc/apt/sources.list.d/freeswitch.list
	apt-get update && apt-get install -y freeswitch-meta-all ; wait
	
	check_status freeswitch
    exporter_conf node_exporter
fi

if [ "$servertype" == "kamailio" ]; then
    exporter_conf node_exporter
	echo "installaing kamailio server"
	echo "deb http://deb.kamailio.org/kamailio51 stretch main" > /etc/apt/sources.list.d/kamailio.list
	wget -O- http://deb.kamailio.org/kamailiodebkey.gpg | apt-key add -
	apt-get update
	apt-get install -y net-tools procps kamailio kamailio-mysql-modules kamailio-tls-modules kamailio-xml-modules gnupg wget
	
	echo "installing rtpengine"
	echo "#####################"
	
	apt-get install -y dpkg-dev
	apt-get install -y git
	git clone https://github.com/sipwise/rtpengine.git /root/rtpengine
	
	cd /root/rtpengine
	echo "##########  installing rtpengine dependancies  ###########"
	apt-get install debhelper default-libmysqlclient-dev gperf iptables-dev libavcodec-dev libavfilter-dev libavformat-dev\
	libavutil-dev libbencode-perl libcrypt-openssl-rsa-perl libcrypt-rijndael-perl libhiredis-dev libio-multiplex-perl libio-socket-inet6-perl\
	libjson-glib-dev libdigest-crc-perl libdigest-hmac-perl libnet-interface-perl libnet-interface-perl libssl-dev libsystemd-dev\
	libxmlrpc-core-c3-dev libcurl4-openssl-dev libevent-dev libpcap0.8-dev markdown unzip nfs-common -y ; wait
	
	echo "#############  installing bcd729 lib  ###################"
	
	VER=1.0.4
	curl https://codeload.github.com/BelledonneCommunications/bcg729/tar.gz/$VER >bcg729_$VER.orig.tar.gz
	tar zxf bcg729_$VER.orig.tar.gz 
	cd /root/rtpengine/bcg729-1.0.4
	git clone https://github.com/ossobv/bcg729-deb.git debian ; wait
	dpkg-buildpackage -us -uc -sa
	cd /root/rtpengine/

	dpkg -i libbcg729-*.deb
	
	cd /root/rtpengine
	dpkg-buildpackage ; wait
	cd /root/
	
	dpkg -i /root/ngcp-rtpengine-daemon_*.deb ngcp-rtpengine-iptables_*.deb ; wait
	apt-get install -y dkms
	dpkg -i /root/ngcp-rtpengine-kernel-dkms_*.deb ; wait
	mv /etc/rtpengine/rtpengine.sample.conf /etc/rtpengine/rtpengine.conf
	sed -i 's/# interface = internal/interface = internal/g' /etc/rtpengine/rtpengine.conf
	mgmtip="$(cat $initfile |grep kamailio |grep ip |grep -v data |awk -F= '{print $2}')"
	dataip="$(cat $initfile |grep kamailio |grep ip |grep data |awk -F= '{print $2}')"
	sed -i "s/12.23.34.45/$dataip/g" /etc/rtpengine/rtpengine.conf
	sed -i "s/23.34.45.54/$mgmtip/g" /etc/rtpengine/rtpengine.conf
	systemctl start ngcp-rtpengine-daemon
	cd /root
	dpkg -i /root/ngcp-rtpengine-daemon-dbgsym_*+*_amd64.deb
	dpkg -i /root/ngcp-rtpengine-utils_*+*_all.deb
	apt-get install module-assistant -y
	cd /root
	dpkg -i /root/ngcp-rtpengine-kernel-source_*+*_all.deb
	sed -i 's/RUN_RTPENGINE=no/RUN_RTPENGINE=yes/g' /etc/default/ngcp-rtpengine-daemon	

	
	systemctl restart ngcp-rtpengine-daemon
	systemctl enable ngcp-rtpengine-daemon
	check_status ngcp-rtpengine-daemon
				
fi

if [ "$servertype" == "xmpp" ]; then
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
 
    exporter_conf node_exporter
fi


echo "script ended. exiting."

#eof


