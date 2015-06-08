#!/bin/bash

## take the last 3 octets in the ifconfig IP & turn into one int

SERVER_ID=$(  /sbin/ifconfig | awk '{ print $2}' | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" |grep -v "127" | sed 's/\.//g' | sed 's/^10//g' )

echo $SERVER_ID
