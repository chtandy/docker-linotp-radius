#!/bin/bash
# test DB connect
export DBSTATUS=no_init
nc -zv ${MYSQL_HOST} ${MYSQL_PORT}
until [ $? -eq 0 ]
do
    sleep 3
    nc -zv ${MYSQL_HOST} ${MYSQL_PORT}
done
# create the database tables
CheckLinotpdb=$(mysql -u ${MYSQL_ROOT_USER} -p${MYSQL_ROOT_PASSWORD} -h ${MYSQL_HOST} -P ${MYSQL_PORT} -e 'show databases;' |grep ${MYSQL_DATABASE})
if [ -z $CheckLinotpdb ]; then
    mysql -u ${MYSQL_ROOT_USER} -p${MYSQL_ROOT_PASSWORD} -h ${MYSQL_HOST} -P ${MYSQL_PORT} -e "create database ${MYSQL_DATABASE};"
    mysql -u ${MYSQL_ROOT_USER} -p${MYSQL_ROOT_PASSWORD} -h ${MYSQL_HOST} -P ${MYSQL_PORT} -e "grant all privileges on ${MYSQL_DATABASE}.* to '${MYSQL_USER}'@'%' identified by '${MYSQL_PASSWORD}';"
    mysql -u ${MYSQL_ROOT_USER} -p${MYSQL_ROOT_PASSWORD} -h ${MYSQL_HOST} -P ${MYSQL_PORT} -e "flush privileges;"
    sed -i "s|sqlalchemy.url =.*|sqlalchemy.url = mysql://${MYSQL_USER}:${MYSQL_PASSWORD}@${MYSQL_HOST}:${MYSQL_PORT}/${MYSQL_DATABASE}|" /etc/linotp2/linotp.ini
    paster setup-app /etc/linotp2/linotp.ini
    export DBSTATUS=init
fi

# 替換 /etc/linotp2/linotp.ini 關於db的設定值
if [ -n ${MYSQL_DATABASE} ] && [ -n ${MYSQL_USER} ] && [ -n ${MYSQL_PASSWORD} ] && [ -n ${MYSQL_HOST} ] && [ -n ${MYSQL_PORT} ]; then
	if [ $DBSTATUS == 'no_init' ]; then
            sed -i "s|sqlalchemy.url =.*|sqlalchemy.url = mysql://${MYSQL_USER}:${MYSQL_PASSWORD}@${MYSQL_HOST}:${MYSQL_PORT}/${MYSQL_DATABASE}|" /etc/linotp2/linotp.ini
        fi
fi

if [ ! -f /etc/linotp2/encKey ] && [ ! -f /data/encKey ]; then
  linotp-create-enckey -f /etc/linotp2/linotp.ini
  chown linotp:apache /etc/linotp2/encKey
  mv /etc/linotp2/encKey /data/encKey
  ln -sf /data/encKey /etc/linotp2/encKey
elif [ ! -f /etc/linotp2/encKey ] && [ -f /data/encKey ]; then
  ln -sf /data/encKey /etc/linotp2/encKey
fi




# set web login user/password
REALM="LinOTP2 admin area"
DIGESTFILE=/etc/linotp2/admins
PWDIGEST=$(echo -n "admin:$REALM:$OTPPASSWD" | md5sum | cut -f1 -d ' ')
echo "admin:$REALM:$PWDIGEST" > $DIGESTFILE


## LinOTP Setting
# chown linotp
chown linotp /etc/linotp2/encKey
chown -R linotp /var/log/linotp
chown -R linotp /etc/linotp2


## Radius Setting

# 新增新設定 /etc/raddb/clients.conf
cat > /etc/raddb/clients.conf << EOF
client localhost {
        ipaddr  = 127.0.0.1
        netmask = 32
        secret  = 'SECRET'
}

EOF

if [ ! -z $RADIUS_ADCONN_NET1 ]; then
cat >> /etc/raddb/clients.conf << EOF
client adconnector {
        ipaddr  = $(echo ${RADIUS_ADCONN_NET1}|cut -d'/' -f1)
        netmask = $(echo ${RADIUS_ADCONN_NET1}|cut -d'/' -f2)
        secret  = '${RADIUS_ADCONN_SECRET}'
}

EOF
fi

if [ ! -z $RADIUS_ADCONN_NET2 ]; then
cat >> /etc/raddb/clients.conf << EOF
client adconnector {
        ipaddr  = $(echo ${RADIUS_ADCONN_NET2}|cut -d'/' -f1)
        netmask = $(echo ${RADIUS_ADCONN_NET2}|cut -d'/' -f2)
        secret  = '${RADIUS_ADCONN_SECRET}'
}
EOF
fi

# 新增linotp perl module 的設定, /etc/raddb/mods-available/perl
cat > /etc/raddb/mods-available/perl << EOF
perl {
     filename = /usr/share/linotp/linotp-auth-freeradius-perl/radius_linotp.pm
}
EOF

ln -s /etc/raddb/mods-available/perl /etc/raddb/mods-enabled/perl

#新增linotp perl config ,/etc/linotp2/rlm_perl.ini
cat > /etc/linotp2/rlm_perl.ini << EOF
URL=https://localhost/validate/simplecheck
REALM=${RADIUS_REALM_OU}
Debug=True
SSL_CHECK=False
EOF

# 新增freeradius linotp virtual host 的設定,/etc/raddb/sites-available/linotp
cat > /etc/raddb/sites-available/linotp << EOF
server default {

listen {
	type = auth
	ipaddr = *
	port = 0

	limit {
	      max_connections = 16
	      lifetime = 0
	      idle_timeout = 30
	}
}

listen {
	ipaddr = *
	port = 0
	type = acct
}



authorize {
        preprocess
        IPASS
        suffix
        ntdomain
        files
        expiration
        logintime
        update control {
                Auth-Type := Perl
        }
        pap
}

authenticate {
	Auth-Type Perl {
		perl
	}
}


preacct {
	preprocess
	acct_unique
	suffix
	files
}

accounting {
	detail
	unix
	-sql
	exec
	attr_filter.accounting_response
}


session {

}


post-auth {
	update {
		&reply: += &session-state:
	}

	-sql
	exec
	remove_reply_message_if_eap
}
}
EOF

ln -s /etc/raddb/sites-available/linotp /etc/raddb/sites-enabled/linotp

# start httpd service
/usr/sbin/httpd $OPTIONS -DFOREGROUND &

# start radius service
chown -R radiusd.radiusd /var/run/radiusd && /usr/sbin/radiusd -C
/usr/sbin/radiusd -d /etc/raddb &

# 若有問題，可以移除以下，主要是要讓Log 輸出到stdout
usermod -aG apache linotp
usermod -aG apache radiusd
chmod 777 /proc/self/fd/1
ln -sf /proc/self/fd/1 /var/log/linotp/linotp.log
ln -sf /proc/self/fd/1 /var/log/radius/radius.log

# deamon
while test ! -z $(ps -ef|grep 'wsgi:linotp'|grep -v grep|awk '{print $1}'); do sleep 60; done
