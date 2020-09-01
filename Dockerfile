FROM centos:7
MAINTAINER cht.andy@gmail.com 
# LinOTP
RUN yum localinstall http://linotp.org/rpm/el7/linotp/x86_64/Packages/LinOTP_repos-1.1-1.el7.x86_64.rpm -y \
  && yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm \
  && yum update -y \
  && yum install nc vim -y \
  && yum install LinOTP LinOTP_mariadb  -y \
  && yum install yum-plugin-versionlock -y \
  && yum versionlock python-repoze-who \
  && yum install LinOTP_apache -y \
  && rm -rf var/cache/yum/ \
  && yum repolist

RUN cp /etc/linotp2/linotp.ini.example /etc/linotp2/linotp.ini \
  && cp /etc/httpd/conf.d/ssl_linotp.conf.template /etc/httpd/conf.d/ssl_linotp.conf \
  && mv /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf.bak

# FreeRadius
RUN yum install git cpanminus freeradius freeradius-perl freeradius-utils perl-App-cpanminus perl-LWP-Protocol-https perl-Try-Tiny -y \
  && cpanm Config::File \
  && rm -rf var/cache/yum/ \
  && yum repolist

RUN  mv /etc/raddb/clients.conf /etc/raddb/clients.conf.back \
  && mv /etc/raddb/users /etc/raddb/users.back \
  && mv /etc/raddb/mods-available/perl /etc/raddb/mods-available/perl.bak \
  && rm -f /etc/raddb/sites-enabled/inner-tunnel /etc/raddb/sites-enabled/default /etc/raddb/mods-enabled/eap \
  && git clone https://github.com/LinOTP/linotp-auth-freeradius-perl.git /usr/share/linotp/linotp-auth-freeradius-perl

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# print httpd log 
RUN ln -sf /proc/self/fd/1 /var/log/httpd/access_log \
  && ln -sf /proc/self/fd/2 /var/log/httpd/error_log

CMD ["/entrypoint.sh"]
