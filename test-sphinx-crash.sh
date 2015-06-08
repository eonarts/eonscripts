#!/bin/bash


SLOG=/var/log/sphinxsearch/searchd.log

crash=$(cat $SLOG |grep "FATAL" )
echo $crash
if [ "$crash" ]; then
   sindex=$( cat $SLOG |grep prealloc  | awk '{print $10}' |uniq |cut -f2 -d"'")
   #echo $sindex | cut -f2 -d"'"
   echo $sindex 
fi

#CIP=$(ifconfig | grep "inet addr" |cut -f2 -d':' | sed 's/Bcast//' | cut -f1 -d' ')
#CIP=$(ifconfig | grep "inet addr" |cut -f2 -d':' | sed 's/Bcast//' | awk '{print $1}')
CIP=$(ifconfig em1 |awk '/inet addr:/ {print $2}'|sed 's/addr://' )
echo $CIP

