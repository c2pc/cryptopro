#switch to root
apt-get update

#####################################
# PHP 7.4:
#####################################
add-apt-repository -y ppa:ondrej/php && apt-get update
apt-get install -y php7.4-fpm php7.4-cli
mkdir /run/php
chown www-data:www-data -R /run/php
mkdir -p /etc/service/php-fpm
cp ./etc/php-fpm/www.conf /etc/php/7.4/fpm/pool.d/www.conf
cp ./services/php-fpm /etc/service/php-fpm/run
chmod +x /etc/service/php-fpm/run

apt-get install -y libboost-dev php7.4-dev libxml2-dev unzip sqlite3 libsqlite3-dev
apt-get install -y php7.4-dom php7.4-bcmath php7.4-mbstring php7.4-curl php-xml php7.4-intl php7.4-pgsql

######################################
## CryptoPro:
## Based on:
## - https://github.com/dbfun/cryptopro
## - https://kinval.ru/ru/cades/phpcades-ubuntu-18-04
######################################
#mv to root dir (dist,certificate)
cd ~
apt-get install -y wget
mkdir /tmp/cryptopro/
cp ./dist/csp.tgz /tmp/cryptopro/
cd /tmp/cryptopro
tar -xvzf csp.tgz
./linux-amd64_deb/install.sh
cd ~
rm -rf /tmp/cryptopro

mkdir /tmp/cades/
cp ./dist/cades.tar.gz /tmp/cades/
cp ./dist/php7_support.patch.zip /tmp/cades/

cd /tmp/cades && tar -xvzf cades.tar.gz
dpkg -i ./cades_linux_amd64/cprocsp-pki-cades-64_2.0.14071-1_amd64.deb
dpkg -i ./cades_linux_amd64/lsb-cprocsp-devel_5.0.11863-5_all.deb
dpkg -i ./cades_linux_amd64/cprocsp-pki-phpcades-64_2.0.14071-1_amd64.deb

PHP_VERSION_BUILD=$(php -i | grep 'PHP Version => ' -m 1 | awk '{split($4,a," "); print a[1]}' | awk '{split($1,a,"-"); print a[1]}') &&
  PHP_VERSION=$(echo "${PHP_VERSION_BUILD}" | awk '{split($1,a,"."); str = sprintf("%s.%s", a[1], a[2]); print str}') &&
  PHP_EXT_DIR=$(php -i | grep 'extension_dir => ' | awk '{print $3}')

mkdir /tmp/php &&
  cd /tmp/php &&
  wget https://www.php.net/distributions/php-${PHP_VERSION_BUILD}.tar.gz &&
  tar -xf php-${PHP_VERSION_BUILD}.tar.gz

cd php-${PHP_VERSION_BUILD}
./configure --prefix=/opt/php
cd /opt/cprocsp/src/phpcades
unzip /tmp/cades/php7_support.patch.zip
patch -p0 <./php7_support.patch
sed -i "s#PHPDIR=/php#PHPDIR=/tmp/php/php-${PHP_VERSION_BUILD}#g" /opt/cprocsp/src/phpcades/Makefile.unix

# https://www.cryptopro.ru/forum2/default.aspx?g=posts&t=11828
# ln -s /opt/cprocsp/lib/amd64/libcppcades.so.2 /opt/cprocsp/lib/amd64/libcppcades.so
# cd /tmp/php/php-${PHP_VERSION_BUILD} && ./configure --prefix=/opt/php

# https://www.cryptopro.ru/forum2/default.aspx?g=posts&m=121907#post121907
# /opt/cprocsp/src/phpcades/Makefile.unix -> set -fPIC -DPIC -> -fPIC -DPIC -fpermissive
eval $(/opt/cprocsp/src/doxygen/CSP/../setenv.sh --64)
make -f Makefile.unix
mv libphpcades.so ${PHP_EXT_DIR}
echo "extension=libphpcades.so" >/etc/php/${PHP_VERSION}/cli/conf.d/20-libphpcades.ini
echo "extension=libphpcades.so" >/etc/php/${PHP_VERSION}/fpm/conf.d/20-libphpcades.ini
php -r "var_dump(class_exists('CPStore'));" | grep -q 'bool(true)'

cd ~
apt-get purge -y php7.4-dev cprocsp-pki-phpcades lsb-cprocsp-devel
rm -rf /opt/cprocsp/src/phpcades && rm -rf /tmp/cades && rm -rf /tmp/php
echo "export PATH=${PATH}:/opt/cprocsp/bin/amd64:/opt/cprocsp/sbin/amd64:/var/www/html/vendor/bin" >>~/.bashrc
apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

#####################################
#  Install certificate:
# http://pushorigin.ru/cryptopro/cryptcp
#####################################
PUBLIC_KEY_FILE_NAME=chincharovpc.cer
PRIVATE_KEY_FOLDER_NAME=ff728aa0.000

cd /root/certificate &&
  CONT_FULL_NAME=$(tail -c+5 "$PRIVATE_KEY_FOLDER_NAME/name.key") &&
  echo "Key container short name: $PRIVATE_KEY_FOLDER_NAME" &&
  cp -R "$PRIVATE_KEY_FOLDER_NAME" /var/opt/cprocsp/keys/root/ &&
  echo -e "Key container installed" &&
  /opt/cprocsp/bin/amd64/certmgr -inst -file "$PUBLIC_KEY_FILE_NAME" -cont "\\\\.\\HDIMAGE\\$CONT_FULL_NAME" &&
  echo "Certificate installed with PrivateKey Link"

cd /root/certificate &&
  wget -O root.pem "http://testca.cryptopro.ru/certsrv/certnew.cer?ReqID=CACert&Renewal=1&Mode=inst&Enc=b64" &&
  /opt/cprocsp/bin/amd64/certmgr -inst -all -store mroot -file root.pem &&
  echo "Root certificate installed"

cd ~ && rm -rf /root/certificate

#####################################
#  Install Invest Site
#####################################
apt install -y git
mkdir /var/www
cd /var/www
git clone https://github.com/c2pc/invest_back html

curl -s http://getcomposer.org/installer | php && mv composer.phar /usr/local/bin/composer
COMPOSER_ALLOW_SUPERUSER=1
echo "export PATH=${PATH}:/opt/cprocsp/bin/amd64:/opt/cprocsp/sbin/amd64:/var/www/html/vendor/bin" >>~/.bashrc

cd html
composer update

chmod -R 775 bootstrap/cache
chmod -R 755 storage
chown -R $USER:www-data storage
chown -R $USER:www-data bootstrap/cache

#####################################
# Nginx
#####################################
apt-get install -y nginx
systemctl enable nginx
systemctl start nginx
cp ./etc/nginx/default /etc/nginx/sites-enabled/default
