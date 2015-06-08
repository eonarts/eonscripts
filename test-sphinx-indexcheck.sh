#!/bin/bash

# first check the main indexes with the indextool
# if corrupt 
#    safe the bad index
#    rebuild the bad index

SPHINX_CNF=/etc/sphinxsearch/sphinx.conf 
INDEX_SCRIPT="/usr/local/bin/sphinx-rotate-indexes "
INDEX_ARRAY=( "orders" "patrons" )
NOW=`date '+%Y%m%d_%H'`
BACKUP_DIR=/var/lib/mysql-binlog/sphinx_bkup

# now run an index check
for IDX in ${INDEX_ARRAY[@]}; do 
   /usr/bin/indextool  -c $SPHINX_CNF --check  $IDX
   ret=$?
   echo "$ret "
   if [ $ret -ne 0 ]; then
	echo "$IDX is corrupt"
	# copy the indexes for checking later
 	# 
	tar -cf  $BACKUP_DIR/${NOW}-${IDX}.tar ${IDX}.*
	# rebuild the index
 	$INDEX_SCRIPT $IDX &
  fi
done
