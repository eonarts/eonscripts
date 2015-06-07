#!/bin/bash

###########################
# test-shard.sh
#
# INPUTS: configuration file called play.conf
# REMOTE SCRIPTS RUN: 
#    puppet-palomino:/home/eoneill/scripts/make_conn.php <# of idle connections to open>
#
# 
# The $SSH_USER} is eoneill. you'll have to run this file as root to do this.
# 

####################################################
# VARIABLES TO BE SET
#
# You make have to create the RAID_DIR directory
####################################################

# set ssh user as root has no privs 
SSH_USER=eoneill
NOW=`date +"%Y%m%d%H%M%S"`
## this number is used by the idle connection job
## for testing
#MAX_CONN=69
MAX_CONN=6995

#MAX_CONN=16995
# This is where the slow query logs go
RAID_DIR=./log/benchlogs
## Misc files
CNF_FILE=play.conf
## default client my.cnf file. pt-log-player needs this
MY_CNF=`grep "^MY_CNF" ${CNF_FILE}  | cut -d= -f2 |sed s"/ //g"`
## Global my.cnf that the db server uses on start up
GLOBAL_MY_CNF=/etc/mysql/my.cnf

## timers
## sleep_time_in_seconds is for the top cmd that runs while the pt-log-player is running
sleep_time_in_seconds=50
#sleep_time_in_seconds=10

# setup db confs. 
USER=`grep "^USER" ${CNF_FILE}  | cut -d= -f2 |sed s"/ //g"`
PWD=`grep "^PWD" ${CNF_FILE}  | cut -d= -f2 |sed s"/ //g"`
PORT=`grep "^PORT" ${CNF_FILE}  | cut -d= -f2 |sed s"/ //g"`

## This is a wrapper script that will run baseline tests on sharddb009i 
## then run the same tests with the diff my.cnf on sharddb009h
## slaves must be stopped on both. 
HOST=<my host>
THREADS_ARRAY=( 8 16 32 1600 )
#THREADS_ARRAY=( 8 16 )


## these are the directories that pt-log player needs
SESSIONS_DIR=`grep "^SESSIONS" ${CNF_FILE}  | cut -d= -f2 |sed s"/ //g"`
RESULTS_DIR=`grep "^RESULTS" ${CNF_FILE}  | cut -d= -f2 |sed s"/ //g"`

## REMOTE SCRIPTS
IDLE_SCRIPT="~eoneill/scripts/make_conn.php"
REMOTE_HOST="puppet-palomino2"

####################################################
# FUNCTIONS
####################################################
function restart_mysqld() {
    RESTART_CMD="service mysql restart"
    SERVER=$1
   (ssh ${SSH_USER}@${SERVER} "sudo $RESTART_CMD" )
   wait $(jobs -p)
   sleep 2
   IS_STARTED=$(ssh ${SSH_USER}@${SERVER} "ps -ef |grep mysqld_safe |grep -v grep ")
   echo $IS_STARTED 
}
function start_slave() {
    (mysql  -u $USER -p$PWD -h $HOST -P $PORT -e "START SLAVE; ")
}

function stop_slave(){
     (mysql -u $USER -p$PWD -h $HOST -P $PORT -e "STOP SLAVE; ")
}

function server_setting_test() {
  #echo $CFG
  S_SETTING=`echo $CFG | cut -d= -f1 | sed s"/ //g"`
  NEW_CFG=`echo $CFG | cut -d= -f2 | sed s"/ //g"`
  #echo $NEW_CFG
  #echo $S_SETTING
  # grab the original so we can set it back
  S_SETTING_START=`mysql -u ${USER} -p${PWD} -h ${HOST} -P $PORT -sNe "show global variables like '${S_SETTING}'" |awk '{print $2}'`
  #echo $S_SETTING_START
  # change the server setting now
  (mysql -u $USER -p$PWD -h $HOST -P $PORT -sNe "SET GLOBAL ${S_SETTING} = ${NEW_CFG}")
  S_SETTING_NOW=`mysql -u ${USER} -p${PWD} -h ${HOST} -P $PORT -sNe "show global variables like '${S_SETTING}'" |awk '{print $2}'`
  echo "now the ${S_SETTING} is ${S_SETTING_NOW}"
}

function find_remote_file(){
   RFILE="$1"
  ## This requires an ssh as eoneill or a user with ssh keys
  ## That user MUST have sudo as checking will include mysql slow logs
  IS_REMOTE_FILE=`ssh ${SSH_USER}@${HOST} "sudo ls ${RFILE}" `
  echo $IS_REMOTE_FILE
  if [ !  $IS_REMOTE_FILE ];then
    echo "Error: $IS_REMOTE_FILE does NOT exist."
    exit 1
  else
    echo "Found remote file $IS_REMOTE_SLOW_LOG"
    echo
  fi
}

function disk_check(){
    if [ ! $1 ]; then
	max_pct_used=90
   else 
	max_pct_used=$1
   fi
   pct_used=$(ssh ${SSH_USER}@${HOST} "df -Ph ${SLOW_QUERY_LOG} " |grep -v Filesystem |awk '{print $5}' |sed 's/%//'  )
   echo "PCT_USED $pct_used "
   if [ $pct_used -gt ${max_pct_used} ];then
          echo "Error: pct_used = ${pct_used}. Clear up some space before running this script."
            start_slave
             exit 1
   fi
}

function prep_slow_log(){
   if [ ! "$SLOW_QUERY_LOG}" ]; then
        SLOW_QUERY_LOG=`mysql -u ${USER} -p${PWD} -h ${HOST} -P $PORT -sNe 'show global variables like "slow_query_log_file"' |awk '{print $2}'`
   fi
  max_pct_used=90
  if [ ! "$1" ]; then
	disk_check $max_pct_used
  else
## ok to copy slow log
        SAMPLE_NAME=$1
        P=$2
        echo "$0 Sample_name is $SAMPLE_NAME"
        echo "Port is $PORT "
	disk_check $max_pct_used
 echo " create this slow log: ${SLOW_QUERY_LOG}_${SAMPLE_NAME}"
        ssh ${SSH_USER}@${HOST} "sudo cp ${SLOW_QUERY_LOG} ${SLOW_QUERY_LOG}_${SAMPLE_NAME}"
        find_remote_file "${SLOW_QUERY_LOG}_${SAMPLE_NAME}"
   fi
        ssh ${SSH_USER}@${HOST} "cat /dev/null |sudo tee ${SLOW_QUERY_LOG}"
        (mysql -u ${USER} -p${PWD} -h ${HOST} -P $PORT  -sNe 'flush logs' )
}
function create_idle_pool() {
     PORT=$1
     THREADS=$2
     SSH_USER="eoneill"
     idle=$(( $MAX_CONN - $THREADS ))
echo " MAX_CONN for $PORT = $MAX_CONN "
     echo " IDLE POOL for $PORT  $idle"
     (ssh ${SSH_USER}@${REMOTE_HOST} "php ${IDLE_SCRIPT} $idle $HOST $PORT " & )
}
function create_results_dir() {
     THREADS=$1
  ## RESULTS DIR is on the puppet server dishing up
     RESULTS_DIR=`grep "^RESULTS" ${CNF_FILE}  | cut -d= -f2 |sed s"/ //g"`
     RESULTS_DIR=${RESULTS_DIR}/${HOST}/results
     RESULTS_DIR=${RESULTS_DIR}/${NOW}-threads${THREADS}
  ## STATS_DIR and STORED_LOG_DIR are ON THE HOST
     STATS_DIR=${NOW}-${HOST}-threads${THREADS}stats
     STORED_LOG_DIR=${RAID_DIR}/threads${THREADS}_logs
     TOP_LOG=${NOW}_top_stats.log
echo "RESULTS DIR: $RESULTS_DIR "
echo "STATS DIR: $STATS_DIR "
echo "stored log $STORED_LOG_DIR "
echo "Top log $TOP_LOG "
  ## Now create the dirs
  ## Results is local to the admin server
    mkdir -p ${RESULTS_DIR}
  ## STATS_DIR & STORED_LOG_DIR are on the DB servers
    echo "make $STATS_DIR and $STORED_LOG_DIR "
    (ssh ${SSH_USER}@${HOST} "mkdir -p ${STATS_DIR} ")
    (ssh ${SSH_USER}@${HOST} "sudo mkdir -p ${STORED_LOG_DIR} " )
}

function take_stats() {
     (ssh ${SSH_USER}@${HOST} "top -bc -n 1 -p \$(pgrep -d',' -f sbin/mysqld) ") >> ${RESULTS_DIR}/${TOP_LOG}
     (mysqladmin -u $USER -p$PWD -h $HOST -P $PORT  status ) >> ${RESULTS_DIR}/${TOP_LOG}
}

function run_pt_log() {
        echo " /mnt/pdb/bin/pt-log-player --only-select  --play $SESSIONS_DIR --base-dir ${RESULTS_DIR} --defaults-file $MY_CNF  --threads $THREADS h=$HOST,u=$USER,P=$PORT " >> ${RESULTS_DIR}/${TOP_LOG}
## choose the my.cnf for the HOST/PORT
        MY_CNF=`grep "^MY_CNF" ${CNF_FILE}  | cut -d= -f2 |sed s"/ //g"`
        echo "the pt-log-player my.cnf is $MY_CNF "
## TURN OFF FOR TESTING LOGGING
       time /mnt/pdb/bin/pt-log-player --only-select  --play $SESSIONS_DIR --base-dir ${RESULTS_DIR} --defaults-file $MY_CNF  --threads $THREADS h=$HOST,u=$USER,p=$PWD ,P=$PORT &

}



function clean_logs() {
  find_remote_file "${SLOW_QUERY_LOG}_${SAMPLE_NAME}"
  ssh ${SSH_USER}@${HOST} "sudo mv  ${SLOW_QUERY_LOG}_${SAMPLE_NAME} ${STORED_LOG_DIR}"
  ZIPFILE=$(basename ${SLOW_QUERY_LOG}_${SAMPLE_NAME})
  ssh ${SSH_USER}@${HOST} "sudo gzip ${STORED_LOG_DIR}/${ZIPFILE}"
  sleep 3
  ssh ${SSH_USER}@${HOST} "sudo tar czf ${STORED_LOG_DIR}/${STATS_DIR}.tar.gz ${STATS_DIR}"
  ssh ${SSH_USER}@${HOST} "cat /dev/null |sudo tee ${SLOW_QUERY_LOG}"
}

function restore_servers () {
   # walk thru the server array & restart mysql & start the slaves     
   for HOST in ${SERVER_ARRAY[@]}; do
	restart_mysqld $HOST
        start_slave
        SLAVE_STATUS=`mysql -u $USER -p$PWD -h $HOST -P $PORT  -sNe "show slave status\G" | grep Slave_SQL_Running | awk '{print $2}' ` 
        echo $SLAVE_STATUS
   done
}


################################################
# MAIN
################################################

MAIN_START=`date `
echo "Test Suite starts now: $MAIN_START"
echo "Check to be sure that the my.cnf is configured for skip_slave_start "
echo "SINGLE HOST ONE INSTANCE TEST. HOST $HOST "
## Is the test safe?
IS_SAFE=`ssh ${SSH_USER}@${HOST} "grep ^skip_slave_start $GLOBAL_MY_CNF "`
if [ ! $IS_SAFE ]; then
	echo "WARNING THE my.cnf does not contain skip_slave_start!"
        echo "TOO dangerous for this test. "
        echo " fix & re-run "
        exit 1
else
        echo "Host $HOST is safe to test"
fi
# clear out old connections
# make sure you can do what needs to be done
  restart_mysqld $HOST
  sleep 4
# stop the slaves
  stop_slave
# check the slave status
  SLOW_QUERY_LOG=`mysql -u ${USER} -p${PWD} -h ${HOST} -P $PORT  -sNe 'show global variables like "slow_query_log_file"' |awk '{print $2}'`
  find_remote_file "${SLOW_QUERY_LOG}"
  SLAVE_STATUS=`mysql -u $USER -p$PWD -h $HOST -P $PORT  -sNe "show slave status\G" | grep Slave_SQL_Running | awk '{print $2}' `
  echo $SLAVE_STATUS
# now let the fun begin!
echo "============================================"
echo " NOW THE FUN Begins "
echo "============================================"
echo " The mysql has been restarted and slow_query_log has been cleared"
echo " "
echo " " 
# THREADS for pt-log-player mean "how many connections are going to run these SELECTS"
## THREADS here are not idle
 for THREADS in ${THREADS_ARRAY[@]}; do 
      echo "THREADS are $THREADS"
      START=`date `
      ## RESTART both 049h and 049h DO NOT START THE SLAVE UNTIL ALL tests are run 
      echo "restarting the mysqld on $HOST "
      sleep 2
echo "testing first"
# Turn off for TESTING
    restart_mysqld $HOST 
    sleep 2
## set long_query_time to equal 0
    (mysql -u $USER -p$PWD -h $HOST -P $PORT  -sNe "SET GLOBAL long_query_time=0")
    (mysql -u $USER -p$PWD -h $HOST -P $PORT  -sNe "show variables like 'long_query_time'") 
## create_results_dir
    create_results_dir $THREADS
## clear slow log of junk
    prep_slow_log
## start the stats log
   echo $START > ${RESULTS_DIR}/${TOP_LOG}
## gather dstats in csv format
   take_stats
## start the idle pool. This number of idle connections is based on Variable MAX_CONN and number of THREADS
   create_idle_pool ${PORT} ${THREADS}
   take_stats
   start_unixtime=`date +"%s"`
   run_pt_log
## now take stats while pt-log-player runs
   take_stats
   count=0
   while [ ${count} -lt ${sleep_time_in_seconds} ]
   do
        take_stats
        sleep 10
        count=$(( $count + 1 ))
   done
## Now wait for the work to finish
   wait $(jobs -p)
  ## dump the INNODB status
  (mysql -u $USER -p$PWD -h $HOST -P $PORT -e "SHOW ENGINE INNODB STATUS\G" ) >> ${RESULTS_DIR}/INNODB_ENGINE_STATUS
  end_unixtime=`date +"%s"`
  echo "$PORT times ${start_unixtime} ${end_unixtime} "
  end_date=`date +"%Y%m%d%H%M%S"`
  diff=$(($end_unixtime-$start_unixtime))
  minutes=$(($diff / 60 ))
  sample_name="${PORT}_${THREADS}__${minutes}min_sample_${end_date}"
  prep_slow_log ${sample_name}
## now clean up the logs
# copy logs to $RAID_DIR/testname
    clean_logs
   END=`date `
   echo "THREAD TEST Start time: $START "
   echo "THREAD TEST End time: $END "
# THREADS
   done 

## restore servers
#restore_servers

MAIN_END=`date `
echo "Start time: $MAIN_START "
echo "End time: $MAIN_END "
exit 
