#!/bin/bash

# This is currently written and tested with a RHEL7 system but should work 
# with most centos/rhel/fedora distributions. Just set your variables in the
# defaults section and give it a try

# Make sure only root can run our script
if [ "$(whoami)" != "root" ]
then
   echo "This script must be run as root or with sudo permissions" 1>&2
   exit 1
fi

#set defaults
REPL_USER='repl'
REPL_PASS='repl'
PGDATA='/var/lib/pgsql/10/data'
POSTGRES_USER='postgres'
POSTGRES_GROUP='postgres'
SERVICE_NAME='postgresql-10'
PGPORT='5432'
SSLMODE='require'
BACKUP='false'
TRIGGER_FILE='/var/lib/pgsql/10/data/failover.txt'
PING_CHECK='true'
MAX_RATE='15M'

###########################################
#### SHOULDN'T HAVE TO EDIT BELOW HERE ####
###########################################

setup_replication() {

  MAX_RATE=${1}
  REPL_HOST=${2}
  REPL_USER=${3}
  REPL_PASS=${4}
  PGDATA=${5}
  PGPORT=${6}
  SSLMODE=${7}
  BACKUP=${8}
  TRIGGER_FILE=${9}
  KEEP=${10}
  COMPRESS=${11}

  if [ "$BACKUP" = "true" ]  
  then

    DATEVAL=`date +%Y%m%d%H%S`
    PGDATADEST="$PGDATA/$DATEVAL"
    if [ "${COMPRESS}" = "true" ]
    then
      BACKUPARGS='-Ft -z'
    fi

    if ! [ -d "${PGDATADEST}" ]
    then

      mkdir -p ${PGDATADEST}
      chown ${POSTGRES_USER}:${POSTGRES_GROUP} ${PGDATADEST}

      if [ $KEEP -gt 0 ]
      then 
        echo "Keeping last $KEEP backups."
        #do work here
        FOLDERCOUNT=`ls ${PGDATA} | wc -l` #note, includes one white space non-folder
        HEADCOUNT=$(expr $FOLDERCOUNT - $KEEP)        

        if [ $HEADCOUNT -gt 0 ] 
        then
          cd ${PGDATA}
          echo "removing below folders:"
          DELFOLDERS=`ls -ltr ${PGDATA} | head -n $HEADCOUNT | awk {'print $9'} | xargs`
          echo "$DELFOLDERS"
          #probably want to add a confirm flag/and prompt check here
          rm -rf $DELFOLDERS
        fi #end headcount
      fi #end integer check
    fi #end pgdata dir check
  else
    PGDATADEST=$PGDATA
    service $SERVICE_NAME stop
    RC=$?

    if [ $RC -ne 0 ] 
    then 
      echo "failed to stop postgres, please investigate"
      exit 1
    fi
  fi

  rm -rf ${PGDATADEST}/*
  RC=$?

  if [ $RC -ne 0 ] 
  then 
    echo "failed to delete information from the postgres data dir, please investigate"
    exit 1
  fi

  echo "Setting up replication with below variables:
  REPL_HOST: $REPL_HOST
  REPL_USER: $REPL_USER
  REPL_PASS: $REPL_PASS
  PGDATA: $PGDATA
  PGPORT: $PGPORT
  SSLMODE: $SSLMODE
  KEEP: $KEEP
  BACKUPARGS: $BACKUPARGS
  MAX_RATE: $MAX_RATE
  "

  su - ${POSTGRES_USER} -c "pg_basebackup -r $MAX_RATE -D ${PGDATADEST} ${BACKUPARGS} --host=${REPL_HOST} --port=${PGPORT} --xlog-method=s -P --username=${REPL_USER} --password" <<EOF
${REPL_PASS}
EOF
  RC=$?

  if [ $RC -ne 0 ] 
  then 
    echo "failed to run successfull pg_basebackup, please investigate"
    exit 1
  fi

  su - ${POSTGRES_USER} -c "echo -e \"standby_mode = 'on'
primary_conninfo = 'host=${REPL_HOST} sslmode=${SSLMODE} user=${REPL_USER} password=${REPL_PASS}'
trigger_file = '${TRIGGER_FILE}'
recovery_target_timeline = 'latest'\" > ${PGDATADEST}/recovery.conf"

  if ! [ "$BACKUP" = "true" ]  
  then
    service $SERVICE_NAME start
    RC=$?

    if [ $RC -ne 0 ] 
    then 
      echo "failed to start postgres, please investigate"
      exit 1
    fi
  fi

}

show_help() {
  echo "This will make the server you are on a slave of the repl_host you provide"
  echo " "
  echo "All of the data in the ${PGDATA} directory will be removed!"
  echo " "
  echo "The repl_host is a required parameter"
  echo " "
  echo "options:"
  echo "-b, --backup		    Backup flag prevents restart of local postgres services when running for backup"
  echo "-d, --pgdata        The postgres data directory (default: ${PGDATA}"
  echo "-c, --compress      Can be used with the backup flag.  Will compress output"
  echo "-h, --help          Show brief help"
  echo "-H, --repl_host     The host to replicate from"
  echo "-k, --keep [x]		  Integer of number of backups to keep. Can only be used with -b|--backup flag is used"
  echo "-n, --no_ping       Disables the ping check before attempting to use the remote source"
  echo "-p, --repl_pass     The replication password to use (default: repl)"
  echo "-P, --pgport        The postgres port (default: ${PGPORT})"
  echo "-r, --max-rate      The maximum transfer rate of data transferred from the server. Values in KB by default add 'M' for MB"
  echo "-s, --sslmode       The sslmode for postgres (disable, allow, prefer, require, "
  echo "                      verify-ca, verify-full).  Default: require"
  echo "-t, --trigger_file  Full path of trigger file to be used in recovery.conf"
  echo "-u, --repl_user     The replication user to use (default: repl)"
  echo " "
}


while test $# -gt 0; do
  case "$1" in
    -b|--backup)
      BACKUP='true'
      shift
      ;;
    -c|--compress)
      COMPRESS='true'
      shift
      ;;
    -d|--pgdata)
      shift
      PGDATA=$1
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    -H|--repl_host)
      shift
      REPL_HOST=$1
      shift
      ;;
    -k|--keep)
      shift
      KEEP=$1
      shift
      ;;
    -n|--no_ping)
      PING_CHECK='false'
      shift
      ;;
    -p|--repl_pass)
      shift
      REPL_PASS=$1
      shift
      ;;
    -P|--pgport)
      shift
      PGPORT=$1
      shift
      ;;
    -r|--max-rate)
      shift
      MAX_RATE=$1
      shift
      ;;
    -s|--sslmode)
      shift
      SSLMODE=$1
      shift
      ;;
    -t|--trigger_file)
      shift
      TRIGGER_FILE=$1
      shift
      ;;
    -u|--repl_user)
      shift
      REPL_USER=$1
      shift
      ;;
    *)
    break
    ;;
  esac
done


#test that host is set or exit
if [ -z "$REPL_HOST" ]
then
  echo "You must specify the replication host"
  echo "use: -H or --repl_host to do so"
  echo " "
  show_help
  exit 1
fi

#test that if keep is specified that we have a backup flag and that it is an integer
if ! [ -z "$KEEP" ]
then
  if ! [ "$BACKUP" == 'true' ]
  then
    echo "You specified the keep flag but did not specify backup.  Keep option can only be used with backups."
    exit 1
  fi
  #test that keep is an integer
  if ! [[ $KEEP =~ ^-?[0-9]+$ ]]
  then
    echo "You specified the keep variable, but it wasn't an integer."
    exit 1
  fi #end integer check
fi #end keep check

#test that host responds to ping or exit
if [ "$PING_CHECK" == 'true' ]
then
  echo "Pinging host..."
  ping -c 1 $REPL_HOST
  RC=$?

  if [ $RC -eq 0 ] 
  then 
    echo "Host found"
  else
    echo "Unable to ping the host you specified"
    exit 1
  fi
fi

#test that the port is open or exit
echo "Testing port (timeout for test is system default)..."
echo "" > /dev/tcp/${REPL_HOST}/${PGPORT}
RC=$?

if [ $RC -eq 0 ]
then
  echo "Port Open"
else
  echo "Unable to connect to the postgres port on the server ${REPL_HOST}"
  exit 1
fi

setup_replication "$MAX_RATE" $REPL_HOST $REPL_USER $REPL_PASS $PGDATA $PGPORT $SSLMODE $BACKUP $TRIGGER_FILE $KEEP $COMPRESS


