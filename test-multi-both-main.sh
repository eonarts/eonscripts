#!/bin/bash

###########################
# test-shard.sh
#
# INPUTS: configuration file called play.conf
#    /home/eoneill/scripts/make_conn.php <# of idle connections to open>
#
# 
# The $SSH_USER} is eoneill. you'll have to run this file as root to do this.
# This test hits both instances with the same number of threads, similar idle pools
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
MAX_CONN=7100

# This is where the slow query logs go
# shard large storage dir
RAID_DIR=/raid0/log/pdb/benchlogs/bothports_active
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

## This is a wrapper script that calls each ports pt-log-player
## then run the same tests with the diff my.cnf on sharddb049h
## slaves must be stopped on both. 
#THREADS_ARRAY=( 8 16 )

THREADS_ARRAY=( 8 16 32 1600 )
HOST=sharddb049h
## Need a port array rather than a server array
PORT_ARRAY=( 3307 3308 )


## these are the directories that pt-log player needs
SESSIONS_DIR=`grep "^SESSIONS" ${CNF_FILE}  | cut -d= -f2 |sed s"/ //g"`

##  SCRIPT called
##  tmulti-player.sh ${PORT} ${THREADS}
# tmulti-player.sh


####################################################
# FUNCTIONS
####################################################
function restart_mysqld() {
    # always restart both instances
    #RESTART_CMD="service mysql restart"
   SERVER=$HOST
   for P in ${PORT_ARRAY[@]}; do 
       RESTART_CMD="/etc/init.d/mysql stop $P"
       (ssh ${SSH_USER}@${SERVER} "sudo $RESTART_CMD" )
       sleep 4
       wait $(jobs -p)
       IS_CHG=$(ssh ${SSH_USER}@${SERVER} "ps -ef |grep mysqld_safe |grep -v grep |grep $P")
       echo $IS_CHG 
   # now start!
       RESTART_CMD="/etc/init.d/mysql start $P"
       (ssh ${SSH_USER}@${SERVER} "sudo $RESTART_CMD" )
       wait $(jobs -p)
       IS_CHG=$(ssh ${SSH_USER}@${SERVER} "ps -ef |grep mysqld_safe |grep -v grep |grep $P")
       echo $IS_CHG 
   done
}
function start_slave() {
    for P in ${PORT_ARRAY[@]}; do 
        (mysql  -u $USER -p$PWD -h $HOST -P $P -e "START SLAVE; ")
    done
}

function stop_slave(){
    for P in ${PORT_ARRAY[@]}; do
        (mysql -u $USER -p$PWD -h $HOST -P $P -e "STOP SLAVE; ")
    done
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


function restore_servers () {
   # walk thru the server array & restart mysql & start the slaves     
  # for HOST in ${SERVER_ARRAY[@]}; do
   for PORT in ${PORT_ARRAY[@]}; do
	restart_mysqld $PORT
	sleep 2
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
echo "This test will STRESS BOTH instances on $PORT1 $PORT2 "
for PORT in ${PORT_ARRAY[@]}; do
    GLOBAL_MY_CNF="/etc/mysql/my-${PORT}.cnf"
    echo "my.cnf is : $GLOBAL_MY_CNF "
    IS_SAFE=`ssh ${SSH_USER}@${HOST} "grep ^skip_slave_start $GLOBAL_MY_CNF "`
    if [ ! $IS_SAFE ]; then
        echo "WARNING THE my.cnf does not contain skip_slave_start!"
        echo "TOO dangerous for this test. "
        echo " fix & re-run "
        exit 1
    else
        echo "Host $HOST $PORT is safe to test"
    fi
done
# clear out old connections
# make sure you can do what needs to be done
  restart_mysqld
  sleep 4
#for HOST in ${SERVER_ARRAY[@]}; do
for P in ${PORT_ARRAY[@]}; do
    stop_slave
done

for PORT in  ${PORT_ARRAY[@]}; do
# find the slow query log
# check the slave status
  SLOW_QUERY_LOG=`mysql -u ${USER} -p${PWD} -h ${HOST} -P $PORT  -sNe 'show global variables like "slow_query_log_file"' |awk '{print $2}'`
  find_remote_file "${SLOW_QUERY_LOG}"
  SLAVE_STATUS=`mysql -u $USER -p$PWD -h $HOST -P $PORT  -sNe "show slave status\G" | grep Slave_SQL_Running | awk '{print $2}' `
  echo $SLAVE_STATUS
done

# now let the fun begin!
echo "============================================"
echo " NOW THE FUN Begins "
echo "============================================"
echo " The mysql has been restarted and slow_query_log has been cleared"
echo " PORTS are important here"
echo " "
echo " Both Ports will be stressed with the same number of active threads "
echo " " 

## THREADS for pt-log-player mean "how many connections are going to run these SELECTS"
## THREADS here are not idle
  for THREADS in ${THREADS_ARRAY[@]}; do 
      echo "THREADS are $THREADS"
     echo "RESULTS DIR : ${RESULTS_DIR} "
## Good tests start with a re-start of the mysql server.
## RESTART both 049h and 049h DO NOT START THE SLAVE UNTIL ALL tests are run 
      echo "restarting the mysqld on $HOST $PORT"
      sleep 2
echo "testing first"
# Turn off for TESTING
    restart_mysqld 
    sleep 2
## set long_query_time to equal 0
 for PORT in  ${PORT_ARRAY[@]}; do
    (mysql -u $USER -p$PWD -h $HOST -P $PORT  -sNe "SET GLOBAL long_query_time=0")
    (mysql -u $USER -p$PWD -h $HOST -P $PORT  -sNe "show variables like 'long_query_time'") 
 done
  for PORT in  ${PORT_ARRAY[@]}; do
      (/bin/bash tmulti-player.sh ${PORT} ${THREADS}) &
  done
  wait $(jobs -p)
END=`date `
echo "Start time: $START "
echo "End time: $END "
# THREADS
   done 

# Turn off for TESTING
## restore servers
restore_servers

MAIN_END=`date `
echo "Start time: $MAIN_START "
  echo "End time: $MAIN_END "
exit 

