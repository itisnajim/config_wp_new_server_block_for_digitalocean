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
PKG_OK=$(dpkg-query -W -f='${Status}' $REQU_PKG 2>/dev/null | grep -c "ok installed")
echo Checking for $REQU_PKG: $PKG_OK
if [ "" = "$PKG_OK" ]; then
    echo "installing $REQU .."
    sudo apt install software-properties-common
fi

REQU_PKG="mariadb-server"
MYSQL_PKG="mysql-server"
PKG_OK=$(dpkg-query -W -f='${Status}' $REQU_PKG 2>/dev/null | grep -c "ok installed")
MYSQL_OK=$(dpkg-query -W -f='${Status}' $MYSQL_PKG 2>/dev/null | grep -c "ok installed")
echo Checking for $REQU_PKG: $PKG_OK
if [ "" = "$PKG_OK" ] || [ "" = "$MYSQL_OK" ]; then
    echo "installing mariadb .."
    add-apt-repository ppa:ondrej/php
    apt-get install mariadb-server mariadb-client php7.0-fpm php7.0-common php7.0-mbstring php7.0-xmlrpc php7.0-soap php7.0-gd php7.0-xml php7.0-intl php7.0-mysql php7.0-cli php7.0-mcrypt php7.0-ldap php7.0-zip php7.0-curl -y;

    mysql_secure_installation

    pause 'Press [Enter] key to continue...'

fi

echo "Configuring php-fpm .."
sed -i 's/(upload_max_filesize = )([0-9]*)(m|M)/upload_max_filesize = 100M/g' /etc/php/7.0/fpm/php.ini
sed -i 's/(max_execution_time = )([0-9]*)/max_execution_time = 360/g' /etc/php/7.0/fpm/php.ini
sed -i 's/(cgi.fix_pathinfo = )([0-9]*)/cgi.fix_pathinfo = 0/g' /etc/php/7.0/fpm/php.ini
pause 'Press [Enter] key to continue...'

echo "Creating MySQL db and user .."
systemctl enable mariadb

BIN_MYSQL=$(which mysql)
DB_HOST="localhost"
DB_NAME="${wsnamedomain}db"
DB_USER="${wsnamedomain}"
DB_PWD_SUFFIX="_Y2021"
DB_PASS="${wsnamedomain}${DB_PWD_SUFFIX}"

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
worker_connections=worker_processes*1024
echo "worker_processes $worker_processes;"
echo "worker_connections ${worker_processes*1024};"
sed -i 's/worker_processes 1;/worker_processes $worker_processes;/g' /etc/nginx/nginx.conf
sed -i 's/worker_processes 1;/worker_connections $worker_connections;/g' /etc/nginx/nginx.conf
pause 'Press [Enter] key to continue...'


echo "Creating NGINX .conf files.."
mkdir -p /etc/nginx/global
cd /etc/nginx/global

echo "common.conf .."

cat > common.conf <<- EOM
# Global configuration file.
# ESSENTIAL : Configure Nginx Listening Port
listen 80;
# ESSENTIAL : Default file to serve. If the first file isn't found, 
index index.php index.html index.htm;
# ESSENTIAL : no favicon logs
location = /favicon.ico {
    log_not_found off;
    access_log off;
}
# ESSENTIAL : robots.txt
location = /robots.txt {
    allow all;
    log_not_found off;
    access_log off;
}
# ESSENTIAL : Configure 404 Pages
error_page 404 /404.html;
# ESSENTIAL : Configure 50x Pages
error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/www;
    }
# SECURITY : Deny all attempts to access hidden files .abcde
location ~ /\. {
    deny all;
}
# PERFORMANCE : Set expires headers for static files and turn off logging.
location ~* ^.+\.(js|css|swf|xml|txt|ogg|ogv|svg|svgz|eot|otf|woff|mp4|ttf|rss|atom|jpg|jpeg|gif|png|ico|zip|tgz|gz|rar|bz2|doc|xls|exe|ppt|tar|mid|midi|wav|bmp|rtf)$ {
    access_log off; log_not_found off; expires 30d;
}
EOM
pause 'Press [Enter] key to continue...'


echo "wordpress.conf .."

cat > wordpress.conf <<- EOM
# WORDPRESS : Rewrite rules, sends everything through index.php and keeps the appended query string intact
location / {
    try_files $uri $uri/ /index.php?q=$uri&$args;
}

# SECURITY : Deny all attempts to access PHP Files in the uploads directory
location ~* /(?:uploads|files)/.*\.php$ {
    deny all;
}
# REQUIREMENTS : Enable PHP Support
location ~ \.php$ {
    # SECURITY : Zero day Exploit Protection
    try_files $uri =404;
    # ENABLE : Enable PHP, listen fpm sock
    fastcgi_split_path_info ^(.+\.php)(/.+)$;
    fastcgi_pass unix:/var/run/php5-fpm.sock;
    fastcgi_index index.php;
    include fastcgi_params;
}
# PLUGINS : Enable Rewrite Rules for Yoast SEO SiteMap
rewrite ^/sitemap_index\.xml$ /index.php?sitemap=1 last;
rewrite ^/([^/]+?)-sitemap([0-9]+)?\.xml$ /index.php?sitemap=$1&sitemap_n=$2 last;

EOM
pause 'Press [Enter] key to continue...'


echo "multisite.conf .."

cat > multisite.conf <<- EOM
# Rewrite rules for WordPress Multi-site.
if (!-e $request_filename) {
rewrite /wp-admin$ $scheme://$host$uri/ permanent;
rewrite ^/[_0-9a-zA-Z-]+(/wp-.*) $1 last;
rewrite ^/[_0-9a-zA-Z-]+(/.*\.php)$ $1 last;
}

EOM
pause 'Press [Enter] key to continue...'


echo "Creating Server Block for $websitedomain .."

sudo rm -f /etc/nginx/sites-enabled/default

cat > "/etc/nginx/sites-available/$websitedomain" <<- EOM
server {
    # URL: Correct way to redirect URL's
    server_name $websitedomain;
    rewrite ^/(.*)$ http://www.$websitedomain/$1 permanent;
    client_max_body_size 100M;

}
server {
    server_name www.$websitedomain;
    root /home/demouser/sitedir;
    access_log /var/log/nginx/www.$websitedomain.access.log;
    error_log /var/log/nginx/www.$websitedomain.error.log;
    include global/common.conf;
    include global/wordpress.conf;
}

EOM
pause 'Press [Enter] key to continue...'


echo "Enabling Server Block Files for $websitedomain .."
sudo ln -s "/etc/nginx/sites-available/$websitedomain" "/etc/nginx/sites-enabled/$websitedomain"

echo "Installing wordpress .."
cd /tmp
wget http://wordpress.org/latest.tar.gz
tar -xzvf latest.tar.gz
mkdir -p "/var/www/$websitedomain/"
cp -r wordpress/* "/var/www/$websitedomain/"
chown -R www-data:www-data "/var/www/$websitedomain"

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
