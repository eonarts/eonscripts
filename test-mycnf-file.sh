#!/bin/bash

MYCNF=/etc/mysql/my.cnf

DATADIR=$(cat ${MYCNF} |grep datadir | awk '{print $3}')
echo $DATADIR
LOGDIR=$(cat ${MYCNF} |grep log_bin | awk '{print $3}' | sed s'/mysql-bin//g')
echo $LOGDIR
TMPDIR=$(cat /etc/mysql/my.cnf |grep tmpdir | awk '{print $3}' )
echo $TMPDIR

if [ ! "$TMPDIR" ]; then
   echo "no tmpdir set"
fi
if [ "$TMPDIR" ]; then
   echo "do this"
fi

