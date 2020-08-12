#!/bin/bash 

@echo off 

read -p 'Enter the Wordpress website domain (e.g: example.com): ' websitedomain
sitedomain="${websitedomain##*.}"
sitename=  "${websitedomain%.*}"

echo "sitename: $sitename, domain: $sitedomain"	

echo "Adjust NGINX Worker Processes & Connections.."

processCount=$(cat /proc/cpuinfo | grep processor)

echo "+process count: $processCount"

sed -i 's/worker_processes 1;/worker_processes $processCount;/g' /etc/nginx/nginx.conf


sed -i 's/worker_processes 1;/worker_connections $(processCount*1024);/g' /etc/nginx/nginx.conf

echo "Enabling Gzip.."

gzip on;
gzip_types text/css text/x-component application/x-javascript application/javascript text/javascript text/x-js text/richtext image/svg+xml text/plain text/xsd text/xsl text/xml image/x-icon;

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

echo "multisite.conf .."

cat > multisite.conf <<- EOM
# Rewrite rules for WordPress Multi-site.
if (!-e $request_filename) {
rewrite /wp-admin$ $scheme://$host$uri/ permanent;
rewrite ^/[_0-9a-zA-Z-]+(/wp-.*) $1 last;
rewrite ^/[_0-9a-zA-Z-]+(/.*\.php)$ $1 last;
}

EOM

echo "Creating Server Blocks.."

rm -f /etc/nginx/sites-enabled/default


