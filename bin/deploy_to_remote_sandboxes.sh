#!/bin/bash
# Initially developed for Continuent, Inc.
# Released under GPL with MySQL Sandbox


[ -z "$MYSQL_VERSION" ] && MYSQL_VERSION=5.5.30
[ -z "$MYSQL_PORT" ]    && MYSQL_PORT=15530
[ -z "$SANDBOX_DIR" ]   && SANDBOX_DIR=remote_sb

NODES_LIST=
TARBALL=

function show_help {
    echo "Deploy to remote sandboxes. "
    echo "Usage: $0 [options] "
    echo '-h               => help'
    echo "-P port          => MySQL port  ($MYSQL_PORT)"
    echo "-d sandbox dir   => sandbox directory name ($SANDBOX_DIR)"
    echo "-m version       => MySQL version ($MYSQL_VERSION)"
    echo "-l list of nodes => list of nodes where to deploy"
    echo "-s server-ids    => list of server IDs to use (default: (10 20 30 40 ...))"
    echo '-t tarball       => MySQL tarball to install remotely (none)'
    echo '-y my.cnf        => MySQL configuration file to use as template (none)'
    echo ""
    echo "This command takes the list of nodes and installs a MySQL sandbox in each one."
    echo "You must have ssh access to the remote nodes, or this script won't work."
    exit 1
}

SERVER_IDS=(`seq 10 10 200`)

args=$(getopt hs:P:m:d:l:t:y: $*)

if [ $? != 0 ]
then
    show_help
fi

set -- $args

for i
do
    case "$i"
        in
        -h)
            show_help
            ;;
        -d)
            export SANDBOX_DIR=$2
            shift
            shift
            ;;
        -l)
            NODES_LIST=$(echo $2 | tr ',' ' ')
            count=0
            for NODE in $NODES_LIST
            do
                NODES[$count]=$NODE
                count=$(($count+1))
            done
            export UPDATE_USER_VALUES=
            shift
            shift
            ;;
        -m)
            export MYSQL_VERSION=$2
            shift
            shift
            ;;
        -P)
            export MYSQL_PORT=$2
            shift
            shift
            ;;
        -s)
            I=0
            for n in $(echo $2 | tr ',' ' ' ) 
            do 
                SERVER_IDS[$I]=$n; 
                I=$(($I+1))
            done
            shift
            shift
            ;;
        -t)
            export TARBALL=$2
            shift
            shift
            ;;
        -y)
            export MY_CNF=$2
            shift
            shift
            ;;
        --)
            shift
            break
            ;;
    esac
done


if [ -z "$NODES_LIST" ]
then
    echo "You must provide a nodes list"
    show_help
fi

# remove the sandbox if it already exists
for HOST in ${NODES[*]} 
do 
    ssh $HOST "if [ -d $HOME/sandboxes/$SANDBOX_DIR ] ; then sbtool -o delete -s $HOME/sandboxes/$SANDBOX_DIR > /dev/null ; fi" 
done

BUILD_SB=$HOME/build_sb.sh

echo "#!/bin/bash" > $BUILD_SB
echo 'SANDBOX_EXISTS=$(for P in `echo $PATH | tr ":" " "` ; do if [ -f $P/make_sandbox ] ; then echo $P/make_sandbox ; fi; done)' >> $BUILD_SB
echo 'if [ -z "$SANDBOX_EXISTS" ] ; then hostname; echo "make_sandbox not found in PATH" ; exit 1; fi' >> $BUILD_SB
MY_TEMPLATE=$my_template$$.cnf
if [ -n "$MY_CNF" ]
then
    if [  ! -f  $MY_CNF ]
    then
        echo "File '$MY_CNF' not found"
        exit 1
    fi
    cp $MY_CNF $HOME/$MY_TEMPLATE
    echo "MY_CNF=\$HOME/$MY_TEMPLATE" >> $BUILD_SB
fi

echo 'SANDBOX_OPTIONS="--no_confirm  --no_show"' >> $BUILD_SB
echo 'if [ -n "$MY_CNF" ] ; then SANDBOX_OPTIONS="$SANDBOX_OPTIONS --my_file=$MY_CNF" ; fi ' >> $BUILD_SB
echo 'SANDBOX_OPTIONS="$SANDBOX_OPTIONS -c server-id=$1 -c default_storage_engine=innodb -c log-bin=mysql-bin -c log-slave-updates -c innodb_flush_log_at_trx_commit=1"' >> $BUILD_SB
echo 'export SANDBOX_OPTIONS="$SANDBOX_OPTIONS -c max_allowed_packet=48M --remote_access=%"' >> $BUILD_SB
if [ -n "$TARBALL" ]
then
    BASE_TARBALL=$(basename $TARBALL)
    echo "make_sandbox \$HOME/opt/mysql/$BASE_TARBALL -- --sandbox_port=$MYSQL_PORT \\" >> $BUILD_SB
else
    echo "make_sandbox $MYSQL_VERSION -- --sandbox_port=$MYSQL_PORT \\" >> $BUILD_SB
fi
echo "   --sandbox_directory=$SANDBOX_DIR  \$SANDBOX_OPTIONS" >> $BUILD_SB
# echo "if [ -f \$HOME/$MY_TEMPLATE ] ; then rm -f \$HOME/$MY_TEMPLATE ; fi "
chmod +x $BUILD_SB

SERVER_ID_COUNTER=0
for HOST in  ${NODES[*]}
do
   if [ -n "$TARBALL" ]
   then
        ssh $HOST 'if [ ! -d $HOME/opt/mysql ] ; then mkdir -p $HOME/opt/mysql ; fi' 
        scp -p $TARBALL $HOST:~/opt/mysql
   fi
   scp -p $BUILD_SB $HOST:$BUILD_SB
   scp -p $HOME/$MY_TEMPLATE $HOST:$MY_TEMPLATE
   ssh $HOST $BUILD_SB ${SERVER_IDS[$SERVER_ID_COUNTER]}
   SERVER_ID_COUNTER=$(($SERVER_ID_COUNTER+1))
done

echo "Connection parameters:"
echo "datadir=~/sandboxes/$SANDBOX_DIR/data"
echo "options file=~/sandboxes/$SANDBOX_DIR/my.sandbox.cnf"
echo "port=$MYSQL_PORT"
echo ""

