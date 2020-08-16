#!/bin/bash 
# init
function pause(){
   read -p "$*"
}

echo "STARTING!! .."

read -p 'Enter the Wordpress website domain (e.g: example.com): ' websitedomain
wsname="${websitedomain%%.*}"
wsdomain="${websitedomain##*.}"
wsnamedomain="${wsname}${wsdomain}"
echo "sitename: $wsname, domain: $wsdomain"	
pause 'Press [Enter] key to continue...'


REQU_PKG="software-properties-common"
#dpkg-query -W -f='${Status}' software-properties-common 2>/dev/null | grep -c "ok installed"
PKG_OK=$(dpkg-query -W -f='${Status}' $REQU_PKG 2>/dev/null | grep -c "ok installed")
echo "Checking for $REQU_PKG: $PKG_OK"
if [ "" = "$PKG_OK" ]; then
    echo "installing $REQU .."
    sudo apt install software-properties-common
fi

REQU_PKG="mariadb-server"
MYSQL_PKG="mysql-server"
#dpkg-query -W -f='${Status}' mariadb-server 2>/dev/null | grep -c "ok installed"
PKG_OK=$(dpkg-query -W -f='${Status}' $REQU_PKG 2>/dev/null | grep -c "ok installed")
#dpkg-query -W -f='${Status}' mysql-server 2>/dev/null | grep -c "ok installed"
MYSQL_OK=$(dpkg-query -W -f='${Status}' $MYSQL_PKG 2>/dev/null | grep -c "ok installed")
echo "Checking for $REQU_PKG: $PKG_OK"
if [ "" = "$PKG_OK" ] || [ "" = "$MYSQL_OK" ]; then
    echo "installing mariadb .."
    add-apt-repository ppa:ondrej/php
    apt-get install mariadb-server mariadb-client php7.1-fpm php7.1-common php7.1-mbstring php7.1-xmlrpc php7.1-soap php7.1-gd php7.1-xml php7.1-intl php7.1-mysql php7.1-cli php7.1-mcrypt php7.1-ldap php7.1-zip php7.1-curl -y;

    mysql_secure_installation

    pause 'Press [Enter] key to continue...'

fi

echo "Configuring php-fpm .."
sed -i 's/(upload_max_filesize = )([0-9]*)(m|M)/upload_max_filesize = 100M/g' /etc/php/7.1/fpm/php.ini
sed -i 's/(max_execution_time = )([0-9]*)/max_execution_time = 360/g' /etc/php/7.1/fpm/php.ini
sed -i 's/(cgi.fix_pathinfo = )([0-9]*)/cgi.fix_pathinfo = 0/g' /etc/php/7.1/fpm/php.ini
pause 'Press [Enter] key to continue...'

echo "Creating MySQL db and user .."
systemctl enable mariadb

BIN_MYSQL=$(which mysql)
DB_HOST="localhost"
DB_NAME="${wsnamedomain}db"
DB_USER="${wsnamedomain}"
DB_PASS_SUFFIX="_Y$(date +"%Y")"
DB_PASS="${wsnamedomain}${DB_PASS_SUFFIX}"

SQL1="CREATE DATABASE IF NOT EXISTS ${DB_NAME};"
SQL2="CREATE USER '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';"
SQL3="GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'%';"
SQL4="FLUSH PRIVILEGES;"

if [ -f /root/.my.cnf ]; then
    $BIN_MYSQL -e "${SQL1}${SQL2}${SQL3}${SQL4}"
else
    # If /root/.my.cnf doesn't exist then it'll ask for root password
    read -p 'Please enter root user MySQL password!: ' mySqlRootPassword

    $BIN_MYSQL -h $DB_HOST -u root -p${mySqlRootPassword} -e "${SQL1}${SQL2}${SQL3}${SQL4}"
fi
echo "mysql bin: $BIN_MYSQL"
pause 'Press [Enter] key to continue...'

NGINX_PKG="nginx"
PKG_OK=$(dpkg-query -W -f='${Status}' $NGINX_PKG 2>/dev/null | grep -c "ok installed")
echo Checking for $NGINX_PKG: $PKG_OK
if [ "" = "$PKG_OK" ]; then
    echo "installing NGINX .."
    sudo apt update
    sudo apt install nginx
    sudo ufw enable
    sudo ufw allow 'Nginx HTTP'

    pause 'Press [Enter] key to continue...'
fi


echo "Adjust NGINX Worker Processes & Connections.."
#worker_processes=$(cat /proc/cpuinfo | grep processor | grep -o -E '[0-9]+')
#if [ worker_processes -lt 1 ]; then
#    worker_processes=1
#fi
worker_processes=4
worker_connections=$(( 1024*worker_processes ))
echo "worker_processes $worker_processes;"
echo "worker_connections $worker_connections;"
sed -i 's/worker_processes 1;/worker_processes $worker_processes;/g' /etc/nginx/nginx.conf
sed -i 's/worker_processes 1;/worker_connections $worker_connections;/g' /etc/nginx/nginx.conf
pause 'Press [Enter] key to continue...'

echo "Creating Server Block for $websitedomain .."

sudo rm -f /etc/nginx/sites-enabled/default

cat > "/etc/nginx/sites-available/$websitedomain" <<- EOM
server {
    listen 80;
    listen [::]:80;
    # URL: Correct way to redirect URL's
    server_name $websitedomain;
    rewrite ^/(.*)$ http://www.$websitedomain/\$1 permanent;
}

server {
    listen 80;
    listen [::]:80;
    server_name www.$websitedomain;
    root /var/www/html/$websitedomain;
    index  index.php index.html index.htm;
    client_max_body_size 100M;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;        
    }

    location ~ \\.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass    unix:/var/run/php/php7.1-fpm.sock;
        fastcgi_param   SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}

EOM
pause 'Press [Enter] key to continue...'

echo "Enabling Server Block Files for $websitedomain .."
sudo ln -s "/etc/nginx/sites-available/$websitedomain" "/etc/nginx/sites-enabled/$websitedomain"

echo "Installing wordpress .."
cd /tmp
wget http://wordpress.org/latest.tar.gz
tar -xzvf latest.tar.gz
mkdir -p "/var/www/$websitedomain"
cp -r wordpress/* "/var/www/$websitedomain"

#cp "/var/www/html/$websitedomain/wp-config-sample.php" "/var/www/html/$websitedomain/wp-config.php"
#sed -i 's/database_name_here/$DB_NAME/g' /var/www/html/$websitedomain/wp-config.php
#sed -i 's/username_here/$DB_USER/g' /var/www/html/$websitedomain/wp-config.php
#sed -i 's/password_here/$DB_PASS/g' /var/www/html/$websitedomain/wp-config.php

WP_Auth_Keys_Salts=$(curl https://api.wordpress.org/secret-key/1.1/salt/)
touch "/var/www/html/$websitedomain/wp-config.php"
cat > "/var/www/html/$websitedomain/wp-config.php" <<- EOM
<?php
/** The name of the database for WordPress */
define( 'DB_NAME', 'database_name_here' );

/** MySQL database username */
define( 'DB_USER', 'username_here' );

/** MySQL database password */
define( 'DB_PASSWORD', 'password_here' );

/** MySQL hostname */
define( 'DB_HOST', 'localhost' );

/** Database Charset to use in creating database tables. */
define( 'DB_CHARSET', 'utf8' );

/** The Database Collate type. Don't change this if in doubt. */
define( 'DB_COLLATE', '' );


$WP_Auth_Keys_Salts

$table_prefix = 'wp_';

define( 'WP_DEBUG', false );

/** Absolute path to the WordPress directory. */
if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}

/** Sets up WordPress vars and included files. */
require_once ABSPATH . 'wp-settings.php';

EOM


sudo chown -R www-data:www-data "/var/www/$websitedomain"
sudo chmod -R 755 /var/www/html

pause 'Press [Enter] key to continue...'


echo "Enabling Nginx and Php"
systemctl restart php7.0-fpm
systemctl enable php7.0-fpm
sudo service nginx reload; 

echo "sitename: $wsname, domain: $wsdomain"	
echo "db host: $DB_HOST"
echo "db name: $DB_NAME"
echo "db user: $DB_USER"
echo "db pwd: $DB_PASS"

echo "DONE!!"
