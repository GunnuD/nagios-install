#!/bin/sh

# Automatically install Nagios and Nagios plugins on multiple popular
# Linux distributions - including Debian, Ubuntu, CentOS, RHEL and others
#
# Copyright (c) 2008 - 2016, Wojciech Kocjan
# 
# This script is licensed under BSD license
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
# 
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

NAGIOS_VERSION=4.1.1
NAGIOS_PLUGINS_VERSION=2.1.1

# needed for older Linux distributions such as Ubuntu 12 or Debian 7
WGET="wget --no-check-certificate"

# Install prerequisites
if which apt-get >/dev/null 2>/dev/null ; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update || exit 1
  apt-get -y upgrade || exit 1
  apt-get -y install wget gcc make binutils cpp \
    libpq-dev libmysqlclient-dev \
    libssl1.0.0 libssl-dev pkg-config \
    libgd2-xpm-dev libgd-tools \
    perl libperl-dev libnet-snmp-perl snmp \
    apache2 apache2-utils libapache2-mod-php5 \
    unzip tar gzip || exit 1
elif yum --help >/dev/null 2>/dev/null ; then
  yum -y update || exit 1
  yum -y install wget gcc make imake binutils cpp \
    postgresql-devel mysql-libs mysql-devel \
    openssl openssl-devel pkgconfig \
    gd gd-devel gd-progs libpng libpng-devel \
    libjpeg libjpeg-devel perl perl-devel \
    net-snmp net-snmp-devel net-snmp-perl net-snmp-utils \
    httpd php \
    unzip tar gzip || exit 1
else
  echo "Unknown or not supported packaging system"
  exit 1
fi
# Determine web server username
if [ -d /etc/apache2 ] ; then
  USER_RESULT=`grep -rh '^ *User \|APACHE_RUN_USER=' /etc/apache2 | grep -v '^ *User .*APACHE_RUN_USER'`
elif [ -d /etc/httpd ] ; then
  USER_RESULT=`grep -rh '^ *User ' /etc/httpd`
else
  USER_RESULT=''
fi

# Parse the output if available or determine user based on known values
if [ "x$USER_RESULT" != "x" ] ; then
  WEB_USER=`echo "$USER_RESULT" | sed 's,^\s*User\s\+,,;s,^.*APACHE_RUN_USER=,,'`
else
  for NAME in apache www-data daemon ; do
    if id -u $NAME >/dev/null 2>/dev/null ; then
      WEB_USER=$NAME
      break
    fi
  done
fi

if [ "x$WEB_USER" = "x" ] ; then
  echo "Unable to determine web server username"
  exit 1
fi

# Fail on errors when setting up Nagios and Nagios plugins
set -e

# Set up users and groups
groupadd nagios
groupadd nagioscmd
useradd -g nagios -G nagioscmd -d /opt/nagios nagios
if [ "x$WEB_USER" != "x" ] ; then
  usermod -G nagioscmd $WEB_USER
fi

# create required directories and ensure proper ownership permissiosn
mkdir -p /opt/nagios /etc/nagios /var/nagios
chown root:root /etc/nagios /opt/nagios
chown nagios:nagios /var/nagios
chmod 0755 /opt/nagios /etc/nagios

# Prepare compilation directory
rm -fR /tmp/nagios-src ; mkdir -p /tmp/nagios-src

cd /tmp/nagios-src

# Compile Nagios
$WGET -O nagios.tar.gz https://assets.nagios.com/downloads/nagioscore/releases/nagios-$NAGIOS_VERSION.tar.gz
tar -xzf nagios.tar.gz ; rm nagios.tar.gz
cd nagios-$NAGIOS_VERSION

sh configure \
  --prefix=/opt/nagios \
  --sysconfdir=/etc/nagios \
  --localstatedir=/var/nagios \
  --libexecdir=/opt/nagios/plugins \
  --with-command-group=nagioscmd

make all
make install
make install-commandmode
make install-config
make install-init

# Compile Nagios plugins
cd /tmp/nagios-src
$WGET -O nagios-plugins.tar.gz http://www.nagios-plugins.org/download/nagios-plugins-$NAGIOS_PLUGINS_VERSION.tar.gz
tar -xzf nagios-plugins.tar.gz ; rm nagios-plugins.tar.gz

cd nagios-plugins-$NAGIOS_PLUGINS_VERSION

sh configure \
  --prefix=/opt/nagios \
  --sysconfdir=/etc/nagios \
  --localstatedir=/var/nagios \
  --libexecdir=/opt/nagios/plugins

make all
make install

# re-apply permissions
chown root:root /etc/nagios /opt/nagios
chown nagios:nagios /var/nagios
chmod 0755 /opt/nagios /etc/nagios

for DIR in /etc/apache2 /etc/httpd ; do
  if [ -d "$DIR" ] ; then
    HTTPD_CONFIG_DIR=$DIR
    break
  fi
done

# for Ubuntu/Debian, enable cgi and auth_basic modules
if which a2enmod >/dev/null 2>/dev/null ; then
  a2enmod cgi
  a2enmod auth_basic
fi

if [ "x$HTTPD_CONFIG_DIR" != "x" ] ; then
  if [ -d "$HTTPD_CONFIG_DIR/conf-available" ] && [ -d "$HTTPD_CONFIG_DIR/conf-enabled" ] ; then
    HTTPD_CONFIG_FILE="$HTTPD_CONFIG_DIR/conf-available/nagios.conf"
    HTTPD_CONFIG_LINK="$HTTPD_CONFIG_DIR/conf-enabled/010-nagios.conf"
  elif [ -d "$HTTPD_CONFIG_DIR/conf.d" ] ; then
    HTTPD_CONFIG_FILE="$HTTPD_CONFIG_DIR/conf.d/nagios.conf"
  fi
fi

if [ "x$HTTPD_CONFIG_FILE" != "x" ] ; then
  cat >$HTTPD_CONFIG_FILE <<EOF
ScriptAlias /nagios/cgi-bin /opt/nagios/sbin
Alias /nagios /opt/nagios/share
<Location "/nagios">
AuthName "Nagios Access"
AuthType Basic
AuthUserFile /etc/nagios/htpasswd.users
require valid-user
</Location>
<Directory "/opt/nagios/share">
AllowOverride None
Options +ExecCGI -MultiViews +SymLinksIfOwnerMatch
Require all granted
Order allow,deny
Allow from all
</Directory>
<Directory "/opt/nagios/sbin">
AllowOverride None
Options +ExecCGI -MultiViews +SymLinksIfOwnerMatch
Require all granted
Order allow,deny
Allow from all
</Directory>
EOF

  cp /dev/null /etc/nagios/htpasswd.groups
  htpasswd -b -c /etc/nagios/htpasswd.users nagiosadmin nagiosadmin

  if [ "x$HTTPD_CONFIG_LINK" != "x" ] ; then
    ln -s $HTTPD_CONFIG_FILE $HTTPD_CONFIG_LINK
  fi
else
  echo "Unable to locate Apache configuration directory - skipping web server configuration"
  exit 1
fi

# cleanup
cd /
rm -fR /tmp/nagios-src

echo "Congratulations! Nagios and standard plugins are now installed."
