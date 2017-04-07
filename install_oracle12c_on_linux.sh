#!/bin/bash
### file header ###############################################################
#: NAME:          install_oracle12c_on_linux.sh
#: SYNOPSIS:      install_oracle12c_on_linux.sh INSTALL
#: DESCRIPTION:   install oracle 12c R2 on redhat family linux x86_64 silently
#: RETURN CODES:  0-SUCCESS, 1-FAILURE
#: RUN AS:        root
#: AUTHOR:        andrei.jeleznov <andrei.jeleznov@gmail.com>
#: VERSION:       1.0-SNAPSHOT
#: URL:           https://github.com/anjel-/install-oracle-12c-on-redhat-linux-silently.git
#: CHANGELOG:
#: DATE:          AUTHOR:             CHANGES:
#: 08.03.2017     anjel-              initial implementation
### external parameters #######################################################
set +x
_REMOVE_DOWNLOADED_FILES="${_REMOVE_DOWNLOADED_FILES:-0}"                 # flag to remove downloaded files: 1=true,0=false
MOUNT_POINT="${MOUNT_POINT:-/u00}"                                        # mount point for a dedicated partition
ORACLE_BASE="${ORACLE_BASE:-${MOUNT_POINT}/app/oracle}"
ORACLE_HOME="${ORACLE_HOME:-${ORACLE_BASE}/product/12.2.0.1/dbhome_1}"
INSTALLATION_DIR="${INSTALLATION_DIR:-$ORACLE_BASE/install}"               # forder for installation files
DATABASE_ARCHIVE="${DATABASE_ARCHIVE:-linuxx64_12201_database.zip}"
ORACLE_URL="http://www.oracle.com/technetwork/database/enterprise-edition/downloads/index.html"
PREINSTALL_PACKAGE="${PREINSTALL_PACKAGE:-installed oracle-rdbms-server-12cR1-preinstall.x86_64}"
PREINSTALL_ARCHIVE="${PREINSTALL_ARCHIVE:-oracle-rdbms-server-12cR1-preinstall-1.0-14.el6.x86_64.rpm}"
PREINSTALL_URL="${PREINSTALL_URL:-https://public-yum.oracle.com/repo/OracleLinux/OL6/8/base/x86_64/getPackage}"
### internal parameters #######################################################
readonly SUCCESS=0 FAILURE=1
readonly FALSE=0  TRUE=1
exitcode=$SUCCESS
### service parameters ########################################################
set +x
_TRACE="${_TRACE:-0}"       # 0-FALSE, 1-print traces
_DEBUG="${_DEBUG:-1}"       # 0-FALSE, 1-print debug messages
_FAILFAST="${_FAILFAST:-1}" # 0-run to the end, 1-stop at the first failure
_DRYRUN="${_DRYRUN:-0}"     # 0-FALSE, 1-send no changes to remote systems
_UNSET="${_UNSET:-0}"       # 0-FALSE, 1-treat unset parameters as an error
TIMEFORMAT='[TIME] %R sec %P%% util'
(( _DEBUG )) && echo "[DEBUG] _TRACE=\"$_TRACE\" _DEBUG=\"$_DEBUG\" _FAILFAST=\"$_FAILFAST\" "
(( _DEBUG )) && echo "[DEBUG] Running with ORACLE_BASE=\"$ORACLE_BASE\" and INSTALLATION_DIR=\"$INSTALLATION_DIR\" "
# set shellopts ###############################################################
(( _TRACE )) && set -x || set +x
(( _FAILFAST )) && { set -o pipefail; } || true
(( _UNSET )) && set -u || set +u
### functions #################################################################
###
function die { #@ print ERR message and exit
	(( _FAILFAST )) && printf "[ERR] %s\n" "$@" >&2 || printf "[WARN] %s\n" "$@" >&2
	(( _FAILFAST )) && exit $FAILURE || { exitcode=$FAILURE; true; }
} #die
###
function print { #@ print qualified message
  local level="INFO"
  (( _DEBUG )) && level="DEBUG"||true
  (( _DRYRUN )) && level="DRYRUN+$level"||true
  printf "[$level] %s\n" "$@"
} #print
###
function initialize { #@ initialization of the script
  (( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
	(( _DEBUG )) && print "Initializing the variables"
  INSTALL_RSP="db_inst.rsp"
  CONFIG_RSP="dbca.rsp"
  NET_RSP="netca.rsp"
  PATH=$ORACLE_HOME/bin:$ORACLE_HOME/OPatch/:/usr/sbin:$PATH
  LD_LIBRARY_PATH=$ORACLE_HOME/lib:/usr/lib
  CLASSPATH=$ORACLE_HOME/jlib:$ORACLE_HOME/rdbms/jlib
  REQUIRED_SPACE_GB=15 #Prerequisites for diskspace in GB
} #initialize
###
function check_for_space { #@ USAGE: test prerequisites
	(( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  (( _DEBUG )) && print "Checking for space"
  local tmp="$(df -PBG ${MOUNT_POINT}|tail -1|awk '{print $4}')"
  tmp="${tmp%G}"
  (( tmp < REQUIRED_SPACE_GB )) && die "There is not enough available space. It needs at least $REQUIRED_SPACE_GB GB available."||true
} #check_for_space
###
function checkPreconditions { #@ test prerequisites for the whole script
  (( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
	(( _DEBUG )) && print "Checking the preconditions for the whole script"
  check_for_space
  [[ ! -d $INSTALLATION_DIR ]]&& mkdir -p $INSTALLATION_DIR||true
} #checkPreconditions
###
function prepare_intallation_media { #@ prepares installation sources
	(( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  (( _DEBUG )) && print "Preparing the installation media"
  if [[ ! -d $INSTALLATION_DIR/database ]];then
    if [[ -f ./$DATABASE_ARCHIVE ]];then
      unzip -d $INSTALLATION_DIR ./$DATABASE_ARCHIVE
    else
      die "Please, download $DATABASE_ARCHIVE from $ORACLE_URL"
    fi
    [[ -d $INSTALLATION_DIR/database ]]|| die "could not find $INSTALLATION_DIR/database"
    (( _REMOVE_DOWNLOADED_FILES )) && rm -f ./$DATABASE_ARCHIVE||true
  else print "$INSTALLATION_DIR/database already exist"
  fi
} #prepare_intallation_media
###
function configure_system { #@ configures the system parameters
	(( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  (( _DEBUG )) && print "Configuring linux for oracle database"
  if ! yum -q list $PREINSTALL_PACKAGE >/dev/null
  then
    [[ ! -f ./$PREINSTALL_ARCHIVE ]] && wget -O ./$PREINSTALL_ARCHIVE $PREINSTALL_URL/$PREINSTALL_ARCHIVE||true
    yum -y install ./$PREINSTALL_ARCHIVE
    (( _REMOVE_DOWNLOADED_FILES )) && rm -f ./$PREINSTALL_ARCHIVE||true
  else
    print "$PREINSTALL_PACKAGE already installed"
  fi
} #configure_system
###
function configure_oracle_user { #@ creates and configures the oracle user
	(( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  (( _DEBUG )) && print "Configuring Users, Groups for Oracle Database"
  local group_name="oinstall"
  local group_id="54321"
  if ! grep -q $group_name /etc/group
  then groupadd -g $group_id $group_name
  fi
  group_name="dba"
  local group_id="54322"
  if ! grep -q $group_name /etc/group
  then groupadd -g $group_id $group_name
  fi
  local user_name="oracle"
  local user_id="54321"
  if ! grep -q $user_name /etc/passwd
  then
    useradd -u $user_id -g oinstall -G dba $user_name
    echo -e "ora\nora" | (passwd --stdin $user_name)
  fi #create oracle
  if ! egrep -q "oracle[[:space:]]*soft[[:space:]]*nofile" /etc/security/limits.conf;then
  print "fixing limits"
cat >>/etc/security/limits.conf <<EOF
oracle        soft   nofile    1024
oracle        hard   nofile    65536
oracle        soft   nproc    16384
oracle        hard   nproc    16384
oracle        soft   stack    10240
oracle        hard   stack    32768
EOF
  fi
  mkdir -p $ORACLE_BASE/oradata
  chown -R oracle:dba $ORACLE_BASE
} #configure_oracle_user
###
function generate_db_inst { #@ generates the db_inst.rsp file
	(( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  (( _DEBUG )) && print "Generating the db_inst.rsp file"
  cat >$INSTALLATION_DIR/$INSTALL_RSP <<EOF
####################################################################
## Copyright(c) Oracle Corporation 1998,2017. All rights reserved.##
##                                                                ##
## Specify values for the variables listed below to customize     ##
## your installation.                                             ##
##                                                                ##
## Each variable is associated with a comment. The comment        ##
## can help to populate the variables with the appropriate        ##
## values.                                                        ##
##                                                                ##
## IMPORTANT NOTE: This file contains plain text passwords and    ##
## should be secured to have read permission only by oracle user  ##
## or db administrator who owns this installation.                ##
##                                                                ##
####################################################################
#-------------------------------------------------------------------------------
# Do not change the following system generated value.
#-------------------------------------------------------------------------------
oracle.install.responseFileVersion=/oracle/install/rspfmt_dbinstall_response_schema_v12.2.0

#-------------------------------------------------------------------------------
# Specify the installation option.
# It can be one of the following:
#   - INSTALL_DB_SWONLY
#   - INSTALL_DB_AND_CONFIG
#   - UPGRADE_DB
#-------------------------------------------------------------------------------
oracle.install.option=INSTALL_DB_SWONLY
#-------------------------------------------------------------------------------
# Specify the Unix group to be set for the inventory directory.
#-------------------------------------------------------------------------------
UNIX_GROUP_NAME=dba
#-------------------------------------------------------------------------------
# Specify the location which holds the inventory files.
# This is an optional parameter if installing on
# Windows based Operating System.
#-------------------------------------------------------------------------------
INVENTORY_LOCATION=${ORACLE_BASE}/oraInventory
#-------------------------------------------------------------------------------
# Specify the complete path of the Oracle Home.
#-------------------------------------------------------------------------------
ORACLE_HOME=${ORACLE_HOME}
#-------------------------------------------------------------------------------
# Specify the complete path of the Oracle Base.
#-------------------------------------------------------------------------------
ORACLE_BASE=${ORACLE_BASE}
#-------------------------------------------------------------------------------
# Specify the installation edition of the component.
#
# The value should contain only one of these choices.
#   - EE     : Enterprise Edition
#-------------------------------------------------------------------------------
oracle.install.db.InstallEdition=EE
###############################################################################
#                                                                             #
# PRIVILEGED OPERATING SYSTEM GROUPS                                          #
# ------------------------------------------                                  #
# Provide values for the OS groups to which SYSDBA and SYSOPER privileges     #
# needs to be granted. If the install is being performed as a member of the   #
# group "dba", then that will be used unless specified otherwise below.       #
#                                                                             #
# The value to be specified for OSDBA and OSOPER group is only for UNIX based #
# Operating System.                                                           #
#                                                                             #
###############################################################################
#------------------------------------------------------------------------------
# The OSDBA_GROUP is the OS group which is to be granted SYSDBA privileges.
#-------------------------------------------------------------------------------
oracle.install.db.OSDBA_GROUP=dba
#------------------------------------------------------------------------------
# The OSOPER_GROUP is the OS group which is to be granted SYSOPER privileges.
# The value to be specified for OSOPER group is optional.
#------------------------------------------------------------------------------
oracle.install.db.OSOPER_GROUP=dba
#------------------------------------------------------------------------------
# The OSBACKUPDBA_GROUP is the OS group which is to be granted SYSBACKUP privileges.
#------------------------------------------------------------------------------
oracle.install.db.OSBACKUPDBA_GROUP=dba
#------------------------------------------------------------------------------
# The OSDGDBA_GROUP is the OS group which is to be granted SYSDG privileges.
#------------------------------------------------------------------------------
oracle.install.db.OSDGDBA_GROUP=dba
#------------------------------------------------------------------------------
# The OSKMDBA_GROUP is the OS group which is to be granted SYSKM privileges.
#------------------------------------------------------------------------------
oracle.install.db.OSKMDBA_GROUP=dba
#------------------------------------------------------------------------------
# The OSRACDBA_GROUP is the OS group which is to be granted SYSRAC privileges.
#------------------------------------------------------------------------------
oracle.install.db.OSRACDBA_GROUP=dba
#------------------------------------------------------------------------------
# Specify whether to enable the user to set the password for
# My Oracle Support credentials. The value can be either true or false.
# If left blank it will be assumed to be false.
#
# Example    : SECURITY_UPDATES_VIA_MYORACLESUPPORT=true
#------------------------------------------------------------------------------
SECURITY_UPDATES_VIA_MYORACLESUPPORT=false
#------------------------------------------------------------------------------
# Specify whether user doesn't want to configure Security Updates.
# The value for this variable should be true if you don't want to configure
# Security Updates, false otherwise.
#
# The value can be either true or false. If left blank it will be assumed
# to be true.
#
# Example    : DECLINE_SECURITY_UPDATES=false
#------------------------------------------------------------------------------
DECLINE_SECURITY_UPDATES=true
EOF
  chown oracle:dba $INSTALLATION_DIR/$INSTALL_RSP
} #generate_db_inst
###
function generate_netca { #@ generates the netca.rsp file
	(( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  (( _DEBUG )) && print "Generating the netca.rcp file"
cat >$INSTALLATION_DIR/$NET_RSP <<EOF
######################################################################
## Copyright(c) 1998, 2016 Oracle Corporation. All rights reserved. ##
##                                                                  ##
## Specify values for the variables listed below to customize your  ##
## installation.                                                    ##
##                                                                  ##
## Each variable is associated with a comment. The comment          ##
## identifies the variable type.                                    ##
##                                                                  ##
## Please specify the values in the following format:               ##
##                                                                  ##
##         Type         Example                                     ##
##         String       "Sample Value"                              ##
##         Boolean      True or False                               ##
##         Number       1000                                        ##
##         StringList   {"String value 1","String Value 2"}         ##
##                                                                  ##
######################################################################
##                                                                  ##
## This sample response file causes the Oracle Net Configuration    ##
## Assistant (NetCA) to complete an Oracle Net configuration during ##
## a custom install of the Oracle12c server which is similar to     ##
## what would be created by the NetCA during typical Oracle12c      ##
## install. It also documents all of the NetCA response file        ##
## variables so you can create your own response file to configure  ##
## Oracle Net during an install the way you wish.                   ##
##                                                                  ##
######################################################################
[GENERAL]
RESPONSEFILE_VERSION="12.2"
CREATE_TYPE="CUSTOM"
#-------------------------------------------------------------------------------
# Name       : SHOW_GUI
# Datatype   : Boolean
# Description: This variable controls appearance/suppression of the NetCA GUI,
# Pre-req    : N/A
# Default    : TRUE
# Note:
# This must be set to false in order to run NetCA in silent mode.
# This is a substitute of "/silent" flag in the NetCA command line.
# The command line flag has precedence over the one in this response file.
# This feature is present since 10.1.0.3.
#-------------------------------------------------------------------------------
SHOW_GUI=false
#-------------------------------------------------------------------------------
# Name       : LOG_FILE
# Datatype   : String
# Description: If present, NetCA will log output to this file in addition to the
#	       standard out.
# Pre-req    : N/A
# Default    : NONE
# Note:
# 	This is a substitute of "/log" in the NetCA command line.
# The command line argument has precedence over the one in this response file.
# This feature is present since 10.1.0.3.
#-------------------------------------------------------------------------------
#LOG_FILE=""/oracle12cHome/network/tools/log/netca.log""
[oracle.net.ca]
#INSTALLED_COMPONENTS;StringList;list of installed components
# The possible values for installed components are:
# "net8","server","client","aso", "cman", "javavm"
INSTALLED_COMPONENTS={"server","net8","javavm"}
#INSTALL_TYPE;String;type of install
# The possible values for install type are:
# "typical","minimal" or "custom"
INSTALL_TYPE=""typical""
#LISTENER_NUMBER;Number;Number of Listeners
# A typical install sets one listener
LISTENER_NUMBER=1
#LISTENER_NAMES;StringList;list of listener names
# The values for listener are:
# "LISTENER","LISTENER1","LISTENER2","LISTENER3", ...
# A typical install sets only "LISTENER"
LISTENER_NAMES={"LISTENER"}
#LISTENER_PROTOCOLS;StringList;list of listener addresses (protocols and parameters separated by semicolons)
# The possible values for listener protocols are:
# "TCP;1521","TCPS;2484","NMP;ORAPIPE","IPC;IPCKEY","VI;1521"
# For multiple listeners, separate them with commas ex "TCP;1521","TCPS;2484"
# For multiple protocols in single listener, separate them with "&" ex  "TCP;1521&TCPS;2484"
# A typical install sets only "TCP;1521"
LISTENER_PROTOCOLS={"TCP;1521"}
#LISTENER_START;String;name of the listener to start, in double quotes
LISTENER_START=""LISTENER""
#NAMING_METHODS;StringList;list of naming methods
# The possible values for naming methods are:
# LDAP, TNSNAMES, ONAMES, HOSTNAME, NOVELL, NIS, DCE
# A typical install sets only: "TNSNAMES","ONAMES","HOSTNAMES"
# or "LDAP","TNSNAMES","ONAMES","HOSTNAMES" for LDAP
NAMING_METHODS={"TNSNAMES","ONAMES","HOSTNAME"}
#NSN_NUMBER;Number;Number of NetService Names
# A typical install sets one net service name
NSN_NUMBER=1
#NSN_NAMES;StringList;list of Net Service names
# A typical install sets net service name to "EXTPROC_CONNECTION_DATA"
NSN_NAMES={"EXTPROC_CONNECTION_DATA"}
#NSN_SERVICE;StringList;Oracle12c database's service name
# A typical install sets Oracle12c database's service name to "PLSExtProc"
NSN_SERVICE={"PLSExtProc"}
#NSN_PROTOCOLS;StringList;list of coma separated strings of Net Service Name protocol parameters
# The possible values for net service name protocol parameters are:
# "TCP;HOSTNAME;1521","TCPS;HOSTNAME;2484","NMP;COMPUTERNAME;ORAPIPE","VI;HOSTNAME;1521","IPC;IPCKEY"
# A typical install sets parameters to "IPC;EXTPROC"
NSN_PROTOCOLS={"TCP;HOSTNAME;1521"}
EOF
  chown oracle:dba $INSTALLATION_DIR/$NET_RSP
} #generate_netca
###
function generate_dbca { #@ generates the dbca.rsp file
	(( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  (( _DEBUG )) && print "Generating the dbca.rsp file"
  if [[ -f $INSTALLATION_DIR/$CONFIG_RSP ]];then
    _FAILFAST=0 die "found existing $INSTALLATION_DIR/$CONFIG_RSP. It will be used"
    return
  fi
  cat >$INSTALLATION_DIR/$CONFIG_RSP <<EOF
##############################################################################
##                                                                          ##
##                            DBCA response file                            ##
##                            ------------------                            ##
## Copyright(c) Oracle Corporation 1998,2017. All rights reserved.          ##
##                                                                          ##
## Specify values for the variables listed below to customize               ##
## your installation.                                                       ##
##                                                                          ##
## Each variable is associated with a comment. The comment                  ##
## can help to populate the variables with the appropriate                  ##
## values.                                                                  ##
##                                                                          ##
## IMPORTANT NOTE: This file contains plain text passwords and              ##
## should be secured to have read permission only by oracle user            ##
## or db administrator who owns this installation.                          ##
##############################################################################
#-------------------------------------------------------------------------------
# Do not change the following system generated value.
#-------------------------------------------------------------------------------
responseFileVersion=/oracle/assistants/rspfmt_dbca_response_schema_v12.2.0
#-----------------------------------------------------------------------------
# Name          : gdbName
# Datatype      : String
# Description   : Global database name of the database
# Valid values  : <db_name>.<db_domain> - when database domain isn't NULL
#                 <db_name>             - when database domain is NULL
# Default value : None
# Mandatory     : Yes
#-----------------------------------------------------------------------------
gdbName=${ORACLE_SID}
#-----------------------------------------------------------------------------
# Name          : sid
# Datatype      : String
# Description   : System identifier (SID) of the database
# Valid values  : Check Oracle12c Administrator's Guide
# Default value : <db_name> specified in GDBNAME
# Mandatory     : No
#-----------------------------------------------------------------------------
sid=${ORACLE_SID}
#-----------------------------------------------------------------------------
# Name          : templateName
# Datatype      : String
# Description   : Name of the template
# Valid values  : Template file name
# Default value : None
# Mandatory     : Yes
#-----------------------------------------------------------------------------
templateName=General_Purpose.dbc
#-----------------------------------------------------------------------------
# Name          : sysPassword
# Datatype      : String
# Description   : Password for SYS user
# Valid values  : Check Oracle12c Administrator's Guide
# Default value : None
# Mandatory     : Yes
#-----------------------------------------------------------------------------
sysPassword=${ORACLE_PASSWD}
#-----------------------------------------------------------------------------
# Name          : systemPassword
# Datatype      : String
# Description   : Password for SYSTEM user
# Valid values  : Check Oracle12c Administrator's Guide
# Default value : None
# Mandatory     : Yes
#-----------------------------------------------------------------------------
systemPassword=${ORACLE_PASSWD}
#-----------------------------------------------------------------------------
# Name          : emConfiguration
# Datatype      : String
# Description   : Enterprise Manager Configuration Type
# Valid values  : CENTRAL|DBEXPRESS|BOTH|NONE
# Default value : NONE
# Mandatory     : No
#-----------------------------------------------------------------------------
emConfiguration=DBEXPRESS
#-----------------------------------------------------------------------------
# Name          : emExpressPort
# Datatype      : Number
# Description   : Enterprise Manager Configuration Type
# Valid values  : Check Oracle12c Administrator's Guide
# Default value : NONE
# Mandatory     : No, will be picked up from DBEXPRESS_HTTPS_PORT env variable
#                 or auto generates a free port between 5500 and 5599
#-----------------------------------------------------------------------------
emExpressPort=5500
#-----------------------------------------------------------------------------
# Name          : dbsnmpPassword
# Datatype      : String
# Description   : Password for DBSNMP user
# Valid values  : Check Oracle12c Administrator's Guide
# Default value : None
# Mandatory     : Yes, if emConfiguration is specified or
#                 the value of runCVUChecks is TRUE
#-----------------------------------------------------------------------------
dbsnmpPassword=${ORACLE_PASSWD}
#-----------------------------------------------------------------------------
# Name          : characterSet
# Datatype      : String
# Description   : Character set of the database
# Valid values  : Check Oracle12c National Language Support Guide
# Default value : "US7ASCII"
# Mandatory     : NO
#-----------------------------------------------------------------------------
characterSet=${ORACLE_CHARACTERSET}
#-----------------------------------------------------------------------------
# Name          : nationalCharacterSet
# Datatype      : String
# Description   : National Character set of the database
# Valid values  : "UTF8" or "AL16UTF16". For details, check Oracle12c National Language Support Guide
# Default value : "AL16UTF16"
# Mandatory     : No
#-----------------------------------------------------------------------------
nationalCharacterSet=AL16UTF16
#-----------------------------------------------------------------------------
# Name          : initParams
# Datatype      : String
# Description   : comma separated list of name=value pairs. Overrides initialization parameters defined in templates
# Default value : None
# Mandatory     : NO
#-----------------------------------------------------------------------------
initParams=db_recovery_file_dest=${ORACLE_BASE}/oradata/fra,audit_trail=none,audit_sys_operations=false
#-----------------------------------------------------------------------------
# Name          : listeners
# Datatype      : String
# Description   : Specifies list of listeners to register the database with.
#		  By default the database is configured for all the listeners specified in the
#		  $ORACLE_HOME/network/admin/listener.ora
# Valid values  : The list should be comma separated like "listener1,listener2".
# Mandatory     : NO
#-----------------------------------------------------------------------------
#listeners=LISTENER
#-----------------------------------------------------------------------------
# Name          : automaticMemoryManagement
# Datatype      : Boolean
# Description   : flag to indicate Automatic Memory Management is used
# Valid values  : TRUE/FALSE
# Default value : TRUE
# Mandatory     : NO
#-----------------------------------------------------------------------------
automaticMemoryManagement=false
#-----------------------------------------------------------------------------
# Name          : totalMemory
# Datatype      : String
# Description   : total memory in MB to allocate to Oracle
# Valid values  :
# Default value :
# Mandatory     : NO
#-----------------------------------------------------------------------------
totalMemory=4096
EOF
  chown oracle:dba $INSTALLATION_DIR/$CONFIG_RSP
} #generate_dbca
###
function install_oracle_software { #@ installs the Oracle 12c software
	(( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  (( _DEBUG )) && print "Installing the Oracle software"
  if [[ -d $ORACLE_HOME ]];then
    print "ORACLE_HOME=$ORACLE_HOME already has been installed"
    return
  fi
  (( _DEBUG )) && print "Running: $INSTALLATION_DIR/database/runInstaller -silent -force -waitforcompletion -responsefile $INSTALLATION_DIR/$INSTALL_RSP -ignoresysprereqs -ignoreprereq"
  if ! \
  runuser -l oracle -c "$INSTALLATION_DIR/database/runInstaller -silent -force -waitforcompletion -responsefile $INSTALLATION_DIR/$INSTALL_RSP -ignoresysprereqs -ignoreprereq"
  then die "there were errors during software installation"
  fi
  (( _REMOVE_DOWNLOADED_FILES )) &&  rm -rf $INSTALLATION_DIR/database||true
} #install_oracle_software
###
function run_root_postinstall { #@ runs the prost-install tasks as root
	(( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  (( _DEBUG )) && print "Running root post-install tasks"
  (( _DEBUG )) && print "Running: ${ORACLE_BASE}/oraInventory/orainstRoot.sh"
  if [[ ! -f  /etc/oraInst.loc ]];then
    ${ORACLE_BASE}/oraInventory/orainstRoot.sh
  else
    print "/etc/oraInst.loc already exists"
  fi
  (( _DEBUG )) && print "Running: ${ORACLE_HOME}/root.sh"
  if [[ ! -d /opt/ORCLfmap ]];then
    ${ORACLE_HOME}/root.sh
  else
    print "${ORACLE_HOME}/root.sh has already been run"
  fi
} #run_root_postinstall
###
function install_net_configuration { #@ installs Oracle net configuration files
	(( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  (( _DEBUG )) && print "Installing the net configuration"
  if [[ -f $ORACLE_HOME/network/admin/listener.ora ]];then
    print "listener.ora has been already configured."
    return
  fi
  echo "[INFO] Running: $ORACLE_HOME/bin/dbca -silent -responseFile $INSTALLATION_DIR/$NET_RSP"
  if ! \
  runuser -l oracle -c "cd $INSTALLATION_DIR; $ORACLE_HOME/bin/netca -silent -orahome $ORACLE_HOME -responseFile $INSTALLATION_DIR/$NET_RSP"
  then die "errors during netca configuration"
  fi

  if ! grep -q "DEDICATED_THROUGH_BROKER_LISTENER=ON" $ORACLE_HOME/network/admin/listener.ora ;then
  cat >> $ORACLE_HOME/network/admin/listener.ora <<EOF
DEDICATED_THROUGH_BROKER_LISTENER=ON
DIAG_ADR_ENABLED=OFF
EOF
  chown oracle:dba $ORACLE_HOME/network/admin/listener.ora
  fi
  runuser -l oracle -c "$ORACLE_HOME/bin/lsnrctl status"

} #install_net_configuration
###
function gen_oracle_parameters { #@ generates the additional Oracle DB parameters
	(( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  (( _DEBUG )) && print "Creating the ORACLE_SID"||true
  #[SALOGINFRA-5732] changed to XE
  ORACLE_SID="XE"
  (( ${#ORACLE_SID} > 12 )) && ORACLE_SID="${ORACLE_SID:1:12}"||true
  ORACLE_CHARACTERSET="AL32UTF8"
  ORACLE_PASSWD="$(tr -dc A-Za-z0-9_ < /dev/urandom|head -c 8|xargs)"
  (( _DEBUG ))&& print "Generating: ORACLE_SID=$ORACLE_SID ORACLE_CHARACTERSET=$ORACLE_CHARACTERSET"||true
} #gen_oracle_parameters
###
function create_database { #@ creates the Oracle database
	(( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  (( _DEBUG )) && print "Creating the database"
  if [[ -d $ORACLE_BASE/oradata/$ORACLE_SID ]];then
    print "ORACLE_SID=$ORACLE_SID has already been created"
    return
  fi
  print "Running: $ORACLE_HOME/bin/dbca -silent -createDatabase -responseFile $INSTALLATION_DIR/$CONFIG_RSP"
  runuser -l oracle -c "ORACLE_HOME=$ORACLE_HOME $ORACLE_HOME/bin/lsnrctl start;$ORACLE_HOME/bin/dbca -silent -createDatabase -responseFile $INSTALLATION_DIR/$CONFIG_RSP"
} #create_database
###
function prepare_oracle_user { #@ customizes the environment files for oracle user
	(( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  (( _DEBUG )) && print "Prepapring the oracle user env"
  if [[ ! -f ~oracle/setenv.sh ]];then
  cat >>~oracle/setenv.sh <<EOF
export ORACLE_SID=$ORACLE_SID
export ORAENV_ASK=NO
. oraenv
EOF
  chown oracle:dba ~oracle/setenv.sh
  fi

  if [[ ! -f ~oracle/startDB.sh ]];then
  cat >>~oracle/startDB.sh <<'2EOF'
#!/bin/bash
[[ -f ~/setenv.sh ]] && source ~/setenv.sh||true
# Start Listener
lsnrctl start

# Start database
sqlplus / as sysdba << EOF
   STARTUP;
   exit;
EOF
2EOF
  chown oracle:dba ~oracle/startDB.sh
  chmod ug+x ~oracle/startDB.sh
  fi

  if [[ ! -f ~oracle/stopDB.sh ]];then
  cat >>~oracle/stopDB.sh <<'2EOF'
#!/bin/bash
[[ -f ~/setenv.sh ]] && source ~/setenv.sh||true
# Start database
sqlplus / as sysdba << EOF
   SHUTDOWN IMMEDIATE;
   exit;
EOF

# Stop Listener
lsnrctl stop

2EOF
  chown oracle:dba ~oracle/stopDB.sh
  chmod ug+x ~oracle/stopDB.sh
  fi
} #prepare_oracle_user
### function main #############################################################
function main {
  (( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  initialize
  case $CMD in
  INSTALL|install)
  checkPreconditions "$CMD"
  prepare_intallation_media
  configure_system
  configure_oracle_user
  generate_db_inst
  install_oracle_software
  run_root_postinstall
  generate_netca
  install_net_configuration
  gen_oracle_parameters
  generate_dbca
  create_database
  prepare_oracle_user
  print "Done."
  ;;
  *) die "unknown command \"$CMD\" "
  ;;
  esac
} #main
### call main #################################################################
(( $# < 1 )) && die "$(basename $0) needs at least one parameter"
declare CMD="$1" ;shift
set -- "$@"
main "$@"
exit $exitcode
