#!/bin/bash

FILENAME=20131016194123-data-only.sql.gz

echo "current filename is $FILENAME "

FN=$(basename $FILENAME)
echo "FN is $FN"
FN2=`basename $FILENAME`
echo "fn2 is $FN2"

EXT=$(echo $FILENAME |awk -F . '{print $NF}')
echo "extension is $EXT"
