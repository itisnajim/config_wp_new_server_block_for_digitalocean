#!/bin/bash 

@echo off 

echo "Adjust NGINX Worker Processes & Connections"
# toor20NotEasy

processCount="$(cat /proc/cpuinfo | grep processor) "
sed -i 's/worker_processes 1;/worker_processes $processCount;/g' file.txt


