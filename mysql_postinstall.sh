#! /bin/bash

initfile=/var/tmp/wbauto.ini

mysqlpass="$(cat $initfile |grep mysql_password |awk -F= '{print $2}')"

if [ ! -f $initfile ]; then
	echo "there is no wbauto.ini file under /var/tmp/ . exiting... "
	exit 1
fi


touch $LOGFILE

H_NAME="$(hostname | awk -F. '{print $1}')"

servertype="$(cat wbauto.ini |grep $H_NAME |awk -F= '{print $1}' |awk -F_ '{print $1}')"

if [ "$(cat wbauto.ini |grep $H_NAME |awk -F= '{print $1}' |awk -F_ '{print $1}')" == "mysql" ]; then
	
	/usr/bin/expect <<EOF
        spawn mysql -u root -p
        expect "Enter password:" { send "$mysqlpass\r" }
		expect "mysql>" { send "CREATE USER 'mysqld_exporter'@'localhost' IDENTIFIED BY 'password' WITH MAX_USER_CONNECTIONS 3;\r" }
		expect "mysql>" { send "GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'mysqld_exporter'@'localhost';\r" }
		expect "mysql>" { send "exit\r" } 
EOF

fi

echo "mysql post installation finished. exiting.."

#end of script
