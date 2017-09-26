#!/bin/bash

#=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=
# PARAMETERS
#=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=
# $1 = app name
# $2 = app version
# $3 = execution (install, start, stop, restart)
# $4 = db type (mysql, postgresql)

PRODUCT=$1
VERSION=$2
EXECUTION=$3
DBTYPE=$4

# Converting params to lowercase
PRODUCT="$(tr [A-Z] [a-z] <<< "$PRODUCT")"
DBTYPE="$(tr [A-Z] [a-z] <<< "$DBTYPE")"
EXECUTION="$(tr [A-Z] [a-z] <<< "$EXECUTION")"

# SCRIPT LOCATION:
pushd `dirname $0` > /dev/null
SCRIPTPATH=`pwd -P`
popd > /dev/null

ATL=$SCRIPTPATH/atl.sh

VERSIONSTR="${VERSION//.}"
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
DATE=$(date +'%Y-%m-%d')



#=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=
# FUNCTIONS
#=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=

# Writes text in yellow color
function writeyellow() {
	echo -e "${YELLOW}$1${NC}"
}

# Verifies if the product name and version passed to the function as parameters is already installed.
# If it is not installed, lists the versions already installed.
# PARAMETER 1: the product name ('fecru', 'bitbucket', 'bamboo', 'crowd', 'jira-software', 'jira-core', 'jira-servicedesk')
# PARAMETER 2: the product version
function verifyExisting() {
	APPS_PATH="$HOME/atlassian/apps";
	APP_NAME=""
	
	case $1 in
		"fecru" ) APP_NAME="FishEye / Crucible" ;;
		"bitbucket") APP_NAME="Bitbucket Server" ;;
		"bamboo") APP_NAME="Bamboo" ;;
		"crowd") APP_NAME="Crowd" ;;
		"jira-software") APP_NAME="JIRA Software Server" ;;
		"jira-core") APP_NAME="JIRA Core Server" ;;
		"jira-servicedesk") APP_NAME="JIRA Service Desk" ;;
		"confluence") APP_NAME="Confluence Server" ;;
	esac
	
	if [ ! -d "$APPS_PATH/$1" ]; then
		# Product directory does not exist
		writeyellow "\nNo versions of $APP_NAME are installed.\n"
		return 1
	else
		if [ ! -d "$APPS_PATH/$1/$2" ]; then
			# Version directory does not exist
			writeyellow "\n$APP_NAME $2 is not installed. Existing versions are:\n"
			
			LENGTH=${#APPS_PATH}+${#1}+2
			
			for i in $(ls -d $APPS_PATH/$1/*/); do 
				temp=${i:$LENGTH}
				temp=${temp%?}
				writeyellow "-> $temp;"
			done
			echo ""
			return 1 
		else
			# Directory exists
			return 0
		fi
	fi
}

# Verifies if there is something already listening on the port passed to the function as parameter
# PARAMETER 1: the port number
function isListeningOn() {
	if ! lsof -n -i:$1 | grep -q LISTEN; then
		return 1
	else
		return 0
	fi
}

# Downloads the driver and creates the MySQL database schema and user
# PARAMETER 1: the product name
# PARAMETER 2: the driver location
function prepareMysqlDatabase() {
	
	# Determine the latest 5.1 minor version
	VERSIONS=`curl -s http://repo1.maven.org/maven2/mysql/mysql-connector-java/ | grep -o '<a href="5.1.*</a>'`
	VERSIONSPLIT=$(echo $VERSIONS | tr '<a href=\"' '\n')

	REGEX='^[0-9]+([.][0-9]+)+([.][0-9]+)?$'

	MINOR=0

	for LINK in $VERSIONSPLIT
	do
		VERFIX=${LINK///}
	
		if [[ $VERFIX =~ $REGEX ]] ; then
			VERMIN=${VERFIX//5.1.}
	
			if [ $VERMIN -gt $MINOR ]; then
				MINOR=$VERMIN
			fi
		
		fi
	done
	
	DRIVERVERSION="5.1.$MINOR"
	
	# Verify if the driver was already downloaded:
	if [ ! -f "mysql-connector-java-$DRIVERVERSION.jar" ]; then
		writeyellow "Downloading MySQL driver v$DRIVERVERSION"
		wget -q http://repo1.maven.org/maven2/mysql/mysql-connector-java/$DRIVERVERSION/mysql-connector-java-$DRIVERVERSION.jar
	fi

	writeyellow "Installing MySQL driver v$DRIVERVERSION"
	
	if [ ! -d $2 ]; then
		mkdir -p $2
	fi
	
	mv mysql-connector-java-$DRIVERVERSION.jar $2
	writeyellow "MySQL driver v$DRIVERVERSION installed successfully"
	
	writeyellow "Creating MySQL database schema '$1$VERSIONSTR' and user"
	echo ""
	echo "Type the password for MySQL 'root' user:"
	read -s ROOTPWD
	echo ""
	echo "Type the database user name to be granted all privileges in $1$VERSIONSTR:"
	read USRNAME
	echo ""
	echo "Type the database user password:"
	read -s USRPWD
	
	export MYSQL_PWD=$ROOTPWD; # so as to suppress the "Warning: Using a password on the command line interface can be insecure." output
	
	mysql -u root -e "SET GLOBAL default_storage_engine = 'InnoDB';"
	mysql -u root -e "CREATE DATABASE $1$VERSIONSTR CHARACTER SET utf8 COLLATE utf8_bin;"
	mysql -u root -e "GRANT ALL PRIVILEGES ON $1$VERSIONSTR.* TO '$USRNAME'@'localhost' IDENTIFIED BY '$USRPWD';"
	mysql -u root -e "FLUSH PRIVILEGES;"
	
	echo ""
	writeyellow "MySQL database schema '$1$VERSIONSTR' and user '$USRNAME' created successfully!"
}

# Creates the PostgreSQL database schema and user
# PARAMETER 1: the product name
function preparePostgresqlDatabase() {
	writeyellow "Creating PostgreSQL database schema '$1$VERSIONSTR' and user"
	echo ""
	echo "Type the password for PostgreSQL 'postgres' user:"
	read -s ROOTPWD
	echo ""
	echo "Type the database user name to be granted all privileges in $1$VERSIONSTR:"
	read USRNAME
	echo ""
	echo "Type the database user password:"
	read -s USRPWD
	
	export PGPASSWORD=$ROOTPWD; # so as not to ask for the database password
	psql -U postgres -c "CREATE USER $USRNAME PASSWORD '$USRPWD';"
	psql -U postgres -c "CREATE DATABASE $1$VERSIONSTR ENCODING 'UTF-8' OWNER $USRNAME;"
	psql -U postgres -c "GRANT ALL ON DATABASE $1$VERSIONSTR TO $USRNAME;"
	
	echo ""
	writeyellow "PostgreSQL database schema '$1$VERSIONSTR' and user '$USRNAME' created successfully!"
}


# Verifies if the log directory exists in FISHEY_INST. If it does not exist, creates it.
# After that, verifies if the log file exists. If it does not exist, creates it.
# Lastly, shows the log output in the screen.
# PARAMETER: the product version
function FeCruShowLog() {
	
	if [ ! -d "$HOME/atlassian/data/fecru/$1/var/log" ]; then
		mkdir -p $HOME/atlassian/data/fecru/$1/var/log
	fi
	
	if [ ! -f "$HOME/atlassian/data/fecru/$1/var/log/atlassian-fisheye-$DATE.log" ]; then
		touch "$HOME/atlassian/data/fecru/$1/var/log/atlassian-fisheye-$DATE.log"
	fi
	
	writeyellow "\nDisplaying the output from $HOME/atlassian/data/fecru/$1/var/log/atlassian-fisheye-$DATE.log\n"
	tail -f "$HOME/atlassian/data/fecru/$1/var/log/atlassian-fisheye-$DATE.log"
}

# Verifies if the log directory exists in BITBUCKET_HOME. If it does not exist, creates it.
# After that, verifies if the log file exists. If it does not exist, creates it.
# Lastly, shows the log output in the screen.
# PARAMETER: the product version
function BitbucketShowLog() {
	
	if [ ! -d "$HOME/atlassian/data/bitbucket/$1/log" ]; then
		mkdir -p $HOME/atlassian/data/bitbucket/$1/log
	fi
	
	if [ ! -f "$HOME/atlassian/data/bitbucket/$1/log/atlassian-bitbucket.log" ]; then
		touch "$HOME/atlassian/data/bitbucket/$1/log/atlassian-bitbucket.log"
	fi
	
	writeyellow "\nDisplaying the output from $HOME/atlassian/data/bitbucket/$1/log/atlassian-bitbucket.log\n"
	tail -f "$HOME/atlassian/data/bitbucket/$1/log/atlassian-bitbucket.log"
}

# Verifies if the log directory exists in BAMBOO_HOME. If it does not exist, creates it.
# After that, verifies if the log file exists. If it does not exist, creates it.
# Lastly, shows the log output in the screen.
# PARAMETER: the product version
function BambooShowLog() {
	
	if [ ! -d "$HOME/atlassian/data/bamboo/$1/logs" ]; then
		mkdir -p $HOME/atlassian/data/bamboo/$1/logs
	fi
	
	if [ ! -f "$HOME/atlassian/data/bamboo/$1/logs/atlassian-bamboo.log" ]; then
		touch "$HOME/atlassian/data/bamboo/$1/logs/atlassian-bamboo.log"
	fi
	
	writeyellow "\nDisplaying the output from $HOME/atlassian/data/bamboo/$1/logs/atlassian-bamboo.log\n"
	tail -f "$HOME/atlassian/data/bamboo/$1/logs/atlassian-bamboo.log"
}

# Verifies if the log directory exists in CROWD_HOME. If it does not exist, creates it.
# After that, verifies if the log file exists. If it does not exist, creates it.
# Lastly, shows the log output in the screen.
# PARAMETER: the product version
function CrowdShowLog() {
	
	if [ ! -d "$HOME/atlassian/data/crowd/$1/logs" ]; then
		mkdir -p $HOME/atlassian/data/crowd/$1/logs
	fi
	
	if [ ! -f "$HOME/atlassian/data/crowd/$1/logs/atlassian-crowd.log" ]; then
		touch "$HOME/atlassian/data/crowd/$1/logs/atlassian-crowd.log"
	fi
	
	writeyellow "\nDisplaying the output from $HOME/atlassian/data/crowd/$1/logs/atlassian-crowd.log\n"
	tail -f "$HOME/atlassian/data/crowd/$1/logs/atlassian-crowd.log"
}

# Verifies if the log directory exists in JIRA_HOME. If it does not exist, creates it.
# After that, verifies if the log file exists. If it does not exist, creates it.
# Lastly, shows the log output in the screen.
# PARAMETER: the product version
function JiraShowLog() {
	
	if [ ! -d "$HOME/atlassian/data/$1/$2/log" ]; then
		mkdir -p $HOME/atlassian/data/$1/$2/log
	fi
	
	if [ ! -f "$HOME/atlassian/data/$1/$2/log/atlassian-jira.log" ]; then
		touch "$HOME/atlassian/data/$1/$2/log/atlassian-jira.log"
	fi
	
	writeyellow "\nDisplaying the output from $HOME/atlassian/data/$1/$2/log/atlassian-jira.log\n"
	tail -f "$HOME/atlassian/data/$1/$2/log/atlassian-jira.log"
}

# Verifies if the log directory exists in CONFLUENCE_HOME. If it does not exist, creates it.
# After that, verifies if the log file exists. If it does not exist, creates it.
# Lastly, shows the log output in the screen.
# PARAMETER: the product version
function ConfluenceShowLog() {
	
	if [ ! -d "$HOME/atlassian/data/confluence/$1/logs" ]; then
		mkdir -p $HOME/atlassian/data/confluence/$1/logs
	fi
	
	if [ ! -f "$HOME/atlassian/data/confluence/$1/logs/atlassian-confluence.log" ]; then
		touch "$HOME/atlassian/data/confluence/$1/logs/atlassian-confluence.log"
	fi
	
	writeyellow "\nDisplaying the output from $HOME/atlassian/data/confluence/$1/logs/atlassian-confluence.log\n"
	tail -f "$HOME/atlassian/data/confluence/$1/logs/atlassian-confluence.log"
}

#=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=
# VALIDATING PARAMETERS TYPED
#=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=
if [ ! $PRODUCT = "fecru" ] &&  [ ! $PRODUCT = "jira-software" ] && [ ! $PRODUCT = "jira-core" ] && [ ! $PRODUCT = "jira-servicedesk" ] && [ ! $PRODUCT = "bitbucket" ] && [ ! $PRODUCT = "bamboo" ] && [ ! $PRODUCT = "crowd" ] && [ ! $PRODUCT = "confluence" ] && [ ! $PRODUCT = "help" ]; then
	writeyellow "Invalid product type. Valid options are 'fecru', 'bitbucket', 'bamboo', 'jira-software', 'jira-core', 'jira-servicedesk', 'crowd' and 'confluence'. You can also use 'help' for, uh... help. Script will terminate."
	exit 1
fi

if [ -z $PRODUCT ]; then
	PRODUCT="help"

elif [ ! $PRODUCT = "help" ]; then
	if [ -z $VERSION ]; then
		writeyellow "No version specified. Script will terminate."
		exit 1
	fi
	
	if [[ ! $VERSION =~ ^[0-9]+\.[0-9]+ ]]; then
		writeyellow "Invalid version format. Only numbers and dots are allowed. Script will terminate."
		exit 1
	fi
	
	if [ -z $EXECUTION ]; then
		writeyellow "No execution type specified. Script will terminate."
		exit 1
	fi

	if [ ! $EXECUTION = "install" ] &&  [ ! $EXECUTION = "start" ] && [ ! $EXECUTION = "stop" ] && [ ! $EXECUTION = "restart" ]; then
		writeyellow "Invalid execution type. Valid options are 'install', 'start', 'stop' and 'restart'. Script will terminate."
		exit 1
	fi
	
	if [ ! $DBTYPE = "mysql" ] && [ ! $DBTYPE = "postgresql" ]; then
		writeyellow "Invalid database type. Valid options are 'mysql' and 'postgresql'. Script will terminate."
		exit 1
	fi
fi

if [ $PRODUCT = "help" ]; then
	writeyellow "--------------------------------------------\n  WELCOME TO THE ATLASSIAN SUITE INSTALLER\n--------------------------------------------"
	writeyellow "DIRECTORY STRUCTURE:"
	echo "- All application binaries will be placed at $HOME/atlassian/apps/<app_name>/<app_version>"
	echo "- All application data will be placed at $HOME/atlassian/data/<app_name>/<app_version>"
	echo ""
	writeyellow "SOFTWARE REQUIREMENTS:"
	echo "- Please make sure that wget (mandatory), MySQL (optional) and PostgreSQL (optional) are installed."
	echo ""
	writeyellow "USAGE:"
	echo "- Parameter 1: Application Name (fecru | bitbucket | bamboo | jira-software | jira-core | jira-servicedesk | crowd | confluence)"
	echo "- Parameter 2: Application Version"
	echo "- Parameter 3: Execution type (install | start | stop | restart)"
	echo "- Parameter 4: Database Type (mysql | postgresql)"
	echo ""
	echo "- Example   1: atl fecru 4.4.1 install mysql"
	echo "- Example   2: atl jira-core 7.4.0 install postgres"
	echo "- Example   3: atl bitbucket 5.1.0 start"
	echo "- Example   4: atl bamboo 6.1.0 restart"
	echo "- Example   5: atl jira-software 7.4.0 stop"
	echo ""
	writeyellow "CONTACT:"
	echo "- Email: fkraemer@atlassian.com"
	echo ""
	exit 1

#=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=
# FISHEYE / CRUCIBLE 
#=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=
elif [ $PRODUCT = "fecru" ]; then
	
	if [ $EXECUTION = "install" ]; then
		if [ ! -d "$HOME/atlassian/apps/fecru" ]; then
			mkdir -p $HOME/atlassian/apps/fecru
		fi
	
		cd $HOME/atlassian/apps/fecru
	
		# Verify if the directory of the version being installed doesn't already exist. If it does, do not proceed to avoid overwriting
		if [ ! -d $VERSION ]; then
		
			writeyellow "FishEye / Crucible $VERSION installation starting!"
			
			# If that directory does not exist, verify if the archive has already been downloaded
			if [ ! -f "fisheye-$VERSION.zip" ]; then
				# If the archive has not been downloaded yet, verify if the version specified exists
				writeyellow "Validating version specified"
				if [[ `wget -S --spider https://www.atlassian.com/software/fisheye/downloads/binary/fisheye-$VERSION.zip  2>&1 | grep 'HTTP/1.1 200 OK'` ]]; then
					# If the version specified exists, download it
					writeyellow "Version has been validated. Downloading fisheye-$VERSION.zip archive. Please wait..."
					wget -q https://www.atlassian.com/software/fisheye/downloads/binary/fisheye-$VERSION.zip
				else
					writeyellow "Invalid version specified. Installation could not proceed."
					exit 1
				fi
			else
				writeyellow "FishEye / Crucible $VERSION archive has been previously downloaded."
			fi
		
			writeyellow "Extracting fisheye-$VERSION.zip archive to fecru-$VERSION"
			unzip -q fisheye-$VERSION.zip

			writeyellow "Deleting fisheye-$VERSION.zip archive"
			rm fisheye-$VERSION.zip

			writeyellow "Renaming directory fecru-$VERSION to $VERSION"
			mv fecru-$VERSION $VERSION

			writeyellow "Creating FISHEYE_INST directory at $HOME/atlassian/data/$PRODUCT/$VERSION"
			mkdir -p $HOME/atlassian/data/$PRODUCT/$VERSION
			
			if [ ! -z "$DBTYPE" ] ; then
				if [ $DBTYPE = "mysql" ]; then
					
					prepareMysqlDatabase $PRODUCT $VERSION/lib
			
				elif [ $DBTYPE = "postgresql" ]; then
					
					preparePostgresqlDatabase $PRODUCT
					
				fi	
			fi
		
			writeyellow "FishEye / Crucible $VERSION installation finished!"
			
			exec $ATL fecru $VERSION start
		
		else
			writeyellow "FishEye / Crucible $VERSION is already installed. Installation will end so as to avoid overwriting."
		fi
	elif [ $EXECUTION = "start" ]; then
		export FISHEYE_INST=$HOME/atlassian/data/fecru/$VERSION
		
		if verifyExisting $PRODUCT $VERSION; then
			
			if ! isListeningOn 8060; then
				writeyellow "\nStarting FishEye / Crucible $VERSION\n"
				$HOME/atlassian/apps/fecru/$VERSION/bin/start.sh
			else
				writeyellow "\nFishEye / Crucible $VERSION is already running\n"
			fi
			
			FeCruShowLog $VERSION
		fi
	elif [ $EXECUTION = "stop" ]; then
		export FISHEYE_INST=$HOME/atlassian/data/fecru/$VERSION
		
		if verifyExisting $PRODUCT $VERSION; then
			if isListeningOn 8060; then
				writeyellow "\nStopping FishEye / Crucible $VERSION\n"
				$HOME/atlassian/apps/fecru/$VERSION/bin/stop.sh
			else
				writeyellow "\nFishEye / Crucible $VERSION is not running\n"
			fi
		fi
	elif [ $EXECUTION = "restart" ]; then
		export FISHEYE_INST=$HOME/atlassian/data/fecru/$VERSION
		
		if verifyExisting $PRODUCT $VERSION; then
			if isListeningOn 8060; then
				writeyellow "\nStopping FishEye / Crucible $VERSION\n"
				$HOME/atlassian/apps/fecru/$VERSION/bin/stop.sh
			else
				writeyellow "\nFishEye / Crucible $VERSION is not running\n"
			fi
						
			writeyellow "\nStarting FishEye / Crucible $VERSION\n"
			$HOME/atlassian/apps/fecru/$VERSION/bin/start.sh
			FeCruShowLog $VERSION
		fi
	else 
		writeyellow "Invalid execution type specified. Valid params are 'install', 'start', 'stop' and 'restart'."
	fi

#=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=
# BITBUCKET SERVER
#=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=
elif [ $PRODUCT = "bitbucket" ]; then
	
	if [ $EXECUTION = "install" ]; then
		if [ ! -d "$HOME/atlassian/apps/$PRODUCT" ]; then
			mkdir -p $HOME/atlassian/apps/$PRODUCT
		fi
	
		cd $HOME/atlassian/apps/$PRODUCT
	
		# Verify if the directory of the version being installed doesn't already exist. If it does, do not proceed to avoid overwriting
		if [ ! -d $VERSION ]; then
			
			writeyellow "Bitbucket Server $VERSION installation starting!"
		
			# If that directory does not exist, verify if the archive has already been downloaded
			if [ ! -f "atlassian-bitbucket-$VERSION.tar.gz" ]; then
				# If the archive has not been downloaded yet, verify if the version specified exists
				writeyellow "Validating version specified"
				if [[ `wget -S --spider https://www.atlassian.com/software/stash/downloads/binary/atlassian-bitbucket-$VERSION.tar.gz  2>&1 | grep 'HTTP/1.1 200 OK'` ]]; then
					# If the version specified exists, download it
					writeyellow "Version has been validated. Downloading atlassian-bitbucket-$VERSION.tar.gz archive. Please wait..."
					wget -q https://www.atlassian.com/software/stash/downloads/binary/atlassian-bitbucket-$VERSION.tar.gz
				else
					writeyellow "Invalid version specified. Installation could not proceed."
					exit 1
				fi
			else
				writeyellow "Bitbucket Server $VERSION archive has been previously downloaded."
			fi
		
			writeyellow "Extracting atlassian-bitbucket-$VERSION.tar.gz archive to atlassian-bitbucket-$VERSION"
			tar xzf atlassian-bitbucket-$VERSION.tar.gz

			writeyellow "Deleting atlassian-bitbucket-$VERSION.tar.gz archive"
			rm atlassian-bitbucket-$VERSION.tar.gz

			writeyellow "Renaming directory atlassian-bitbucket-$VERSION to $VERSION"
			mv atlassian-bitbucket-$VERSION $VERSION

			writeyellow "Creating BITBUCKET_HOME directory at $HOME/atlassian/data/$PRODUCT/$VERSION"
			mkdir -p $HOME/atlassian/data/$PRODUCT/$VERSION
		
			if [ ! -z "$DBTYPE" ] ; then
				if [ $DBTYPE = "mysql" ]; then
					
					prepareMysqlDatabase $PRODUCT $HOME/atlassian/data/$PRODUCT/$VERSION/lib
			
				elif [ $DBTYPE = "postgresql" ]; then
					
					preparePostgresqlDatabase $PRODUCT
					
				fi	
			fi
		
			writeyellow "Bitbucket Server $VERSION installation finished!"
			
			exec $ATL bitbucket $VERSION start
		
		else
			writeyellow "Bitbucket Server $VERSION is already installed. Installation will end so as to avoid overwriting."
		fi
	elif [ $EXECUTION = "start" ]; then
		export BITBUCKET_HOME=$HOME/atlassian/data/bitbucket/$VERSION
		
		if verifyExisting $PRODUCT $VERSION; then
			
			if ! isListeningOn 7990; then
				writeyellow "\nStarting Bitbucket Server $VERSION\n"
				$HOME/atlassian/apps/bitbucket/$VERSION/bin/start-bitbucket.sh
			else
				writeyellow "\nBitbucket Server $VERSION is already running\n"
			fi
			
			BitbucketShowLog $VERSION
		fi
	elif [ $EXECUTION = "stop" ]; then
		export BITBUCKET_HOME=$HOME/atlassian/data/bitbucket/$VERSION
		
		if verifyExisting $PRODUCT $VERSION; then
			if isListeningOn 7990; then
				writeyellow "\nStopping Bitbucket Server $VERSION\n"
				$HOME/atlassian/apps/bitbucket/$VERSION/bin/stop-bitbucket.sh
			else
				writeyellow "\nBitbucket Server $VERSION is not running\n"
			fi
		fi
	elif [ $EXECUTION = "restart" ]; then
		export BITBUCKET_HOME=$HOME/atlassian/data/bitbucket/$VERSION
		
		if verifyExisting $PRODUCT $VERSION; then
			if isListeningOn 7990; then
				writeyellow "\nStopping Bitbucket Server $VERSION\n"
				$HOME/atlassian/apps/bitbucket/$VERSION/bin/stop-bitbucket.sh
			else
				writeyellow "\nBitbucket Server $VERSION is not running\n"
			fi
						
			writeyellow "\nStarting Bitbucket Server $VERSION\n"
			$HOME/atlassian/apps/bitbucket/$VERSION/bin/start-bitbucket.sh
			BitbucketShowLog $VERSION
		fi
	else 
		writeyellow "Invalid execution type specified. Valid params are 'install', 'start', 'stop' and 'restart'."
	fi

#=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=
# BAMBOO
#=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=
elif [ $PRODUCT = "bamboo" ]; then
	
	if [ $EXECUTION = "install" ]; then
		if [ ! -d "$HOME/atlassian/apps/bamboo" ]; then
			mkdir -p $HOME/atlassian/apps/bamboo
		fi
	
		cd $HOME/atlassian/apps/bamboo
	
		# Verify if the directory of the version being installed doesn't already exist. If it does, do not proceed to avoid overwriting
		if [ ! -d $VERSION ]; then
			
			writeyellow "Bamboo $VERSION installation starting!"
		
			# If that directory does not exist, verify if the archive has already been downloaded
			if [ ! -f "atlassian-bamboo-$VERSION.tar.gz" ]; then
				# If the archive has not been downloaded yet, verify if the version specified exists
				writeyellow "Validating version specified"
				if [[ `wget -S --spider https://www.atlassian.com/software/bamboo/downloads/binary/atlassian-bamboo-$VERSION.tar.gz  2>&1 | grep 'HTTP/1.1 200 OK'` ]]; then
					# If the version specified exists, download it
					writeyellow "Version has been validated. Downloading atlassian-bamboo-$VERSION.tar.gz archive. Please wait..."
					wget -q https://www.atlassian.com/software/bamboo/downloads/binary/atlassian-bamboo-$VERSION.tar.gz
				else
					writeyellow "Invalid version specified. Installation could not proceed."
					exit 1
				fi
			else
				writeyellow "Bamboo $VERSION archive has been previously downloaded."
			fi
		
			writeyellow "Extracting atlassian-bamboo-$VERSION.tar.gz archive to atlassian-bamboo-$VERSION"
			tar xzf atlassian-bamboo-$VERSION.tar.gz

			writeyellow "Deleting atlassian-bamboo-$VERSION.tar.gz archive"
			rm atlassian-bamboo-$VERSION.tar.gz

			writeyellow "Renaming directory atlassian-bamboo-$VERSION to $VERSION"
			mv atlassian-bamboo-$VERSION $VERSION

			writeyellow "Creating BAMBOO_HOME directory at $HOME/atlassian/data/$PRODUCT/$VERSION"
			mkdir -p $HOME/atlassian/data/$PRODUCT/$VERSION
		
			if [ ! -z "$DBTYPE" ] ; then
				if [ $DBTYPE = "mysql" ]; then
					
					prepareMysqlDatabase $PRODUCT $VERSION/lib
			
				elif [ $DBTYPE = "postgresql" ]; then
					
					preparePostgresqlDatabase $PRODUCT
					
				fi	
			fi
		
			writeyellow "Bamboo $VERSION installation finished!"
			
			exec $ATL bamboo $VERSION start
		
		else
			writeyellow "Bamboo $VERSION is already installed. Installation will end so as to avoid overwriting."
		fi
	elif [ $EXECUTION = "start" ]; then
		export BAMBOO_HOME=$HOME/atlassian/data/bamboo/$VERSION
		
		if verifyExisting $PRODUCT $VERSION; then
			
			if ! isListeningOn 8085; then
				writeyellow "\nStarting Bamboo $VERSION\n"
				$HOME/atlassian/apps/bamboo/$VERSION/bin/start-bamboo.sh
			else
				writeyellow "\nBamboo $VERSION is already running\n"
			fi
			
			BambooShowLog $VERSION
		fi
	elif [ $EXECUTION = "stop" ]; then
		export BAMBOO_HOME=$HOME/atlassian/data/bamboo/$VERSION
		
		if verifyExisting $PRODUCT $VERSION; then
			if isListeningOn 8085; then
				writeyellow "\nStopping Bamboo $VERSION\n"
				$HOME/atlassian/apps/bamboo/$VERSION/bin/stop-bamboo.sh
				rm $HOME/atlassian/data/bamboo/$VERSION/jms-store/bamboo/KahaDB/lock
			else
				writeyellow "\nBamboo $VERSION is not running\n"
			fi
		fi
	elif [ $EXECUTION = "restart" ]; then
		export BAMBOO_HOME=$HOME/atlassian/data/bamboo/$VERSION
		
		if verifyExisting $PRODUCT $VERSION; then
			if isListeningOn 8085; then
				writeyellow "\nStopping Bamboo $VERSION\n"
				$HOME/atlassian/apps/bamboo/$VERSION/bin/stop-bamboo.sh
			else
				writeyellow "\nBamboo $VERSION is not running\n"
			fi
						
			writeyellow "\nStarting Bamboo $VERSION\n"
			rm $HOME/atlassian/data/bamboo/$VERSION/jms-store/bamboo/KahaDB/lock
			$HOME/atlassian/apps/bamboo/$VERSION/bin/start-bamboo.sh
			BambooShowLog $VERSION
		fi
	else 
		writeyellow "Invalid execution type specified. Valid params are 'install', 'start', 'stop' and 'restart'."
	fi

#=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=
# CROWD
#=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=/=

elif [ $PRODUCT = "crowd" ]; then
	
	if [ $EXECUTION = "install" ]; then
		if [ ! -d "$HOME/atlassian/apps/$PRODUCT" ]; then
			mkdir -p $HOME/atlassian/apps/$PRODUCT
		fi
	
		cd $HOME/atlassian/apps/$PRODUCT
	
		# Verify if the directory of the version being installed doesn't already exist. If it does, do not proceed to avoid overwriting
		if [ ! -d $VERSION ]; then
			
			writeyellow "Crowd $VERSION installation starting!"
			
			# If that directory does not exist, verify if the archive has already been downloaded
			if [ ! -f "atlassian-crowd-$VERSION.tar.gz" ]; then
				# If the archive has not been downloaded yet, verify if the version specified exists
				writeyellow "Validating version specified"
				if [[ `wget -S --spider https://www.atlassian.com/software/crowd/downloads/binary/atlassian-crowd-$VERSION.tar.gz  2>&1 | grep 'HTTP/1.1 200 OK'` ]]; then
					# If the version specified exists, download it
					writeyellow "Version has been validated. Downloading atlassian-crowd-$VERSION.tar.gz archive. Please wait..."
					wget -q https://www.atlassian.com/software/crowd/downloads/binary/atlassian-crowd-$VERSION.tar.gz
				else
					writeyellow "Invalid version specified. Installation could not proceed."
					exit 1
				fi
			else
				writeyellow "Crowd $VERSION archive has been previously downloaded."
			fi
		
			writeyellow "Extracting atlassian-crowd-$VERSION.tar.gz archive to atlassian-crowd-$VERSION"
			tar xzf atlassian-crowd-$VERSION.tar.gz

			writeyellow "Deleting atlassian-crowd-$VERSION.tar.gz archive"
			rm atlassian-crowd-$VERSION.tar.gz

			writeyellow "Renaming directory atlassian-crowd-$VERSION to $VERSION"
			mv atlassian-crowd-$VERSION $VERSION

			writeyellow "Creating CROWD_HOME directory at $HOME/atlassian/data/$PRODUCT/$VERSION"
			mkdir -p $HOME/atlassian/data/$PRODUCT/$VERSION
			
			
			# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
			# CROWD_HOME is hardcoded at $HOME/atlassian/apps/crowd/$VERSION/crowd-webapp/WEB-INF/classes/crowd-init.properties #
			# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
		
			writeyellow "Configuring CROWD_HOME at crowd-init.properties"
		
			echo "crowd.home=$HOME/atlassian/data/$PRODUCT/$VERSION" >> $HOME/atlassian/apps/$PRODUCT/$VERSION/crowd-webapp/WEB-INF/classes/crowd-init.properties
		
			if [ ! -z "$DBTYPE" ] ; then
				if [ $DBTYPE = "mysql" ]; then
					
					prepareMysqlDatabase $PRODUCT $VERSION/apache-tomcat/lib
			
				elif [ $DBTYPE = "postgresql" ]; then
					
					preparePostgresqlDatabase $PRODUCT
					
				fi	
			fi
		
			writeyellow "Crowd $VERSION installation finished!"
			
			exec $ATL crowd $VERSION start
		
		else
			writeyellow "Crowd $VERSION is already installed. Installation will end so as to avoid overwriting."
		fi
	elif [ $EXECUTION = "start" ]; then
		
		if verifyExisting $PRODUCT $VERSION; then
			
			if ! isListeningOn 8095; then
				writeyellow "\nStarting Crowd $VERSION\n"
				$HOME/atlassian/apps/$PRODUCT/$VERSION/start_crowd.sh
			else
				writeyellow "\nCrowd $VERSION is already running\n"
			fi
			
			CrowdShowLog $VERSION
		fi
	elif [ $EXECUTION = "stop" ]; then
		
		if verifyExisting $PRODUCT $VERSION; then
			if isListeningOn 8095; then
				writeyellow "\nStopping Crowd $VERSION\n"
				$HOME/atlassian/apps/$PRODUCT/$VERSION/stop_crowd.sh
			else
				writeyellow "\nCrowd $VERSION is not running\n"
			fi
		fi
	elif [ $EXECUTION = "restart" ]; then
		
		if verifyExisting $PRODUCT $VERSION; then
			if isListeningOn 8095; then
				writeyellow "\nStopping Crowd $VERSION\n"
				$HOME/atlassian/apps/$PRODUCT/$VERSION/stop_crowd.sh
			else
				writeyellow "\nCrowd $VERSION is not running\n"
			fi
						
			writeyellow "\nStarting Crowd $VERSION\n"
			$HOME/atlassian/apps/$PRODUCT/$VERSION/start_crowd.sh
			CrowdShowLog $VERSION
		fi
	else 
		writeyellow "Invalid execution type specified. Valid params are 'install', 'start', 'stop' and 'restart'."
	fi
elif [ $PRODUCT = "jira-software" ]; then
	
	if [ $EXECUTION = "install" ]; then
		if [ ! -d "$HOME/atlassian/apps/$PRODUCT" ]; then
			mkdir -p $HOME/atlassian/apps/$PRODUCT
		fi
	
		cd $HOME/atlassian/apps/$PRODUCT
	
		# Verify if the directory of the version being installed doesn't already exist. If it does, do not proceed to avoid overwriting
		if [ ! -d $VERSION ]; then
			
			writeyellow "JIRA Software Server $VERSION installation starting!"
		
			# If that directory does not exist, verify if the archive has already been downloaded
			if [ ! -f "atlassian-jira-software-$VERSION.tar.gz" ]; then
				# If the archive has not been downloaded yet, verify if the version specified exists
				writeyellow "Validating version specified"
				if [[ `wget -S --spider https://www.atlassian.com/software/jira/downloads/binary/atlassian-jira-software-$VERSION.tar.gz  2>&1 | grep 'HTTP/1.1 200 OK'` ]]; then
					# If the version specified exists, download it
					writeyellow "Version has been validated. Downloading atlassian-jira-software-$VERSION.tar.gz archive. Please wait..."
					wget -q https://www.atlassian.com/software/jira/downloads/binary/atlassian-jira-software-$VERSION.tar.gz
				else
					writeyellow "Invalid version specified. Installation could not proceed."
					exit 1
				fi
			else
				writeyellow "Jira Software Server $VERSION archive has been previously downloaded."
			fi
		
			writeyellow "Extracting atlassian-jira-software-$VERSION.tar.gz archive to atlassian-jira-software-$VERSION-standalone"
			tar xzf atlassian-jira-software-$VERSION.tar.gz

			writeyellow "Deleting atlassian-jira-software-$VERSION.tar.gz archive"
			rm atlassian-jira-software-$VERSION.tar.gz

			writeyellow "Renaming directory atlassian-jira-software-$VERSION-standalone to $VERSION"
			mv atlassian-jira-software-$VERSION-standalone $VERSION

			writeyellow "Creating JIRA_HOME directory at $HOME/atlassian/data/$PRODUCT/$VERSION"
			mkdir -p $HOME/atlassian/data/$PRODUCT/$VERSION
		
			# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
			# JIRA_HOME is hardcoded at $HOME/atlassian/apps/$PRODUCT/$VERSION/atlassian-jira/WEB-INF/classes/jira-application.properties #
			# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
			
			writeyellow "Configuring JIRA_HOME at jira-application.properties"
		
			echo "jira.home=$HOME/atlassian/data/$PRODUCT/$VERSION" >> $HOME/atlassian/apps/$PRODUCT/$VERSION/atlassian-jira/WEB-INF/classes/jira-application.properties
		
			if [ ! -z "$DBTYPE" ] ; then
				if [ $DBTYPE = "mysql" ]; then
					
					prepareMysqlDatabase "${PRODUCT//-}" $VERSION/lib
			
				elif [ $DBTYPE = "postgresql" ]; then
					
					preparePostgresqlDatabase "${PRODUCT//-}"
					
				fi	
			fi
		
			writeyellow "JIRA Software Server $VERSION installation finished!"
			
			exec $ATL jira-software $VERSION start
		
		else
			writeyellow "JIRA Software Server $VERSION is already installed. Installation will end so as to avoid overwriting."
		fi
	elif [ $EXECUTION = "start" ]; then
		
		if verifyExisting $PRODUCT $VERSION; then
			
			if ! isListeningOn 8080; then
				writeyellow "\nStarting JIRA Software Server $VERSION\n"
				$HOME/atlassian/apps/$PRODUCT/$VERSION/bin/start-jira.sh
			else
				writeyellow "\nJIRA Software Server $VERSION is already running\n"
			fi
			
			JiraShowLog $PRODUCT $VERSION
		fi
	elif [ $EXECUTION = "stop" ]; then
		
		if verifyExisting $PRODUCT $VERSION; then
			if isListeningOn 8080; then
				writeyellow "\nStopping JIRA Software Server $VERSION\n"
				$HOME/atlassian/apps/$PRODUCT/$VERSION/bin/stop-jira.sh
			else
				writeyellow "\nJIRA Software Server $VERSION is not running\n"
			fi
		fi
	elif [ $EXECUTION = "restart" ]; then
		
		if verifyExisting $PRODUCT $VERSION; then
			if isListeningOn 8080; then
				writeyellow "\nStopping JIRA Software Server $VERSION\n"
				$HOME/atlassian/apps/$PRODUCT/$VERSION/bin/stop-jira.sh
			else
				writeyellow "\nJIRA Software Server $VERSION is not running\n"
			fi
						
			writeyellow "\nStarting JIRA Software Server $VERSION\n"
			$HOME/atlassian/apps/$PRODUCT/$VERSION/bin/start-jira.sh
			JiraShowLog $PRODUCT $VERSION
		fi
	else 
		writeyellow "Invalid execution type specified. Valid params are 'install', 'start', 'stop' and 'restart'."
	fi
	
elif [ $PRODUCT = "jira-core" ]; then
	
	if [ $EXECUTION = "install" ]; then
		if [ ! -d "$HOME/atlassian/apps/$PRODUCT" ]; then
			mkdir -p $HOME/atlassian/apps/$PRODUCT
		fi
	
		cd $HOME/atlassian/apps/$PRODUCT
	
		# Verify if the directory of the version being installed doesn't already exist. If it does, do not proceed to avoid overwriting
		if [ ! -d $VERSION ]; then
			
			writeyellow "JIRA Core Server $VERSION installation starting!"
		
			# If that directory does not exist, verify if the archive has already been downloaded
			if [ ! -f "atlassian-jira-core-$VERSION.tar.gz" ]; then
				# If the archive has not been downloaded yet, verify if the version specified exists
				writeyellow "Validating version specified"
				if [[ `wget -S --spider https://www.atlassian.com/software/jira/downloads/binary/atlassian-jira-core-$VERSION.tar.gz  2>&1 | grep 'HTTP/1.1 200 OK'` ]]; then
					# If the version specified exists, download it
					writeyellow "Version has been validated. Downloading atlassian-jira-core-$VERSION.tar.gz archive. Please wait..."
					wget -q https://www.atlassian.com/software/jira/downloads/binary/atlassian-jira-core-$VERSION.tar.gz
				else
					writeyellow "Invalid version specified. Installation could not proceed."
					exit 1
				fi
			else
				writeyellow "Jira Core Server $VERSION archive has been previously downloaded."
			fi
		
			writeyellow "Extracting atlassian-jira-core-$VERSION.tar.gz archive to atlassian-jira-core-$VERSION-standalone"
			tar xzf atlassian-jira-core-$VERSION.tar.gz

			writeyellow "Deleting atlassian-jira-core-$VERSION.tar.gz archive"
			rm atlassian-jira-core-$VERSION.tar.gz

			writeyellow "Renaming directory atlassian-jira-core-$VERSION-standalone to $VERSION"
			mv atlassian-jira-core-$VERSION-standalone $VERSION

			writeyellow "Creating JIRA_HOME directory at $HOME/atlassian/data/$PRODUCT/$VERSION"
			mkdir -p $HOME/atlassian/data/$PRODUCT/$VERSION
		
			# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
			# JIRA_HOME is hardcoded at $HOME/atlassian/apps/$PRODUCT/$VERSION/atlassian-jira/WEB-INF/classes/jira-application.properties #
			# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
			
			writeyellow "Configuring JIRA_HOME at jira-application.properties"
		
			echo "jira.home=$HOME/atlassian/data/$PRODUCT/$VERSION" >> $HOME/atlassian/apps/$PRODUCT/$VERSION/atlassian-jira/WEB-INF/classes/jira-application.properties
		
			if [ ! -z "$DBTYPE" ] ; then
				if [ $DBTYPE = "mysql" ]; then
					
					prepareMysqlDatabase "${PRODUCT//-}" $VERSION/lib
			
				elif [ $DBTYPE = "postgresql" ]; then
					
					preparePostgresqlDatabase "${PRODUCT//-}"
					
				fi	
			fi
		
			writeyellow "JIRA Core Server $VERSION installation finished!"
			
			exec $ATL jira-core $VERSION start
		
		else
			writeyellow "JIRA Core Server $VERSION is already installed. Installation will end so as to avoid overwriting."
		fi
	elif [ $EXECUTION = "start" ]; then
		
		if verifyExisting $PRODUCT $VERSION; then
			
			if ! isListeningOn 8080; then
				writeyellow "\nStarting JIRA Core Server $VERSION\n"
				$HOME/atlassian/apps/$PRODUCT/$VERSION/bin/start-jira.sh
			else
				writeyellow "\nJIRA Core Server $VERSION is already running\n"
			fi
			
			JiraShowLog $PRODUCT $VERSION
		fi
	elif [ $EXECUTION = "stop" ]; then
		
		if verifyExisting $PRODUCT $VERSION; then
			if isListeningOn 8080; then
				writeyellow "\nStopping JIRA Core Server $VERSION\n"
				$HOME/atlassian/apps/$PRODUCT/$VERSION/bin/stop-jira.sh
			else
				writeyellow "\nJIRA Core Server $VERSION is not running\n"
			fi
		fi
	elif [ $EXECUTION = "restart" ]; then
		
		if verifyExisting $PRODUCT $VERSION; then
			if isListeningOn 8080; then
				writeyellow "\nStopping JIRA Core Server $VERSION\n"
				$HOME/atlassian/apps/$PRODUCT/$VERSION/bin/stop-jira.sh
			else
				writeyellow "\nJIRA Core Server $VERSION is not running\n"
			fi
						
			writeyellow "\nStarting JIRA Core Server $VERSION\n"
			$HOME/atlassian/apps/$PRODUCT/$VERSION/bin/start-jira.sh
			JiraShowLog $PRODUCT $VERSION
		fi
	else 
		writeyellow "Invalid execution type specified. Valid params are 'install', 'start', 'stop' and 'restart'."
	fi
	
elif [ $PRODUCT = "jira-servicedesk" ]; then
	
	if [ $EXECUTION = "install" ]; then
		if [ ! -d "$HOME/atlassian/apps/$PRODUCT" ]; then
			mkdir -p $HOME/atlassian/apps/$PRODUCT
		fi
	
		cd $HOME/atlassian/apps/$PRODUCT
	
		# Verify if the directory of the version being installed doesn't already exist. If it does, do not proceed to avoid overwriting
		if [ ! -d $VERSION ]; then
			
			writeyellow "JIRA Service Desk $VERSION installation starting!"
		
			# If that directory does not exist, verify if the archive has already been downloaded
			if [ ! -f "atlassian-servicedesk-$VERSION.tar.gz" ]; then
				# If the archive has not been downloaded yet, verify if the version specified exists
				writeyellow "Validating version specified"
				if [[ `wget -S --spider https://www.atlassian.com/software/jira/downloads/binary/atlassian-servicedesk-$VERSION.tar.gz  2>&1 | grep 'HTTP/1.1 200 OK'` ]]; then
					# If the version specified exists, download it
					writeyellow "Version has been validated. Downloading atlassian-servicedesk-$VERSION.tar.gz archive. Please wait..."
					wget -q https://www.atlassian.com/software/jira/downloads/binary/atlassian-servicedesk-$VERSION.tar.gz
				else
					writeyellow "Invalid version specified. Installation could not proceed."
					exit 1
				fi
			else
				writeyellow "Jira Service Desk $VERSION archive has been previously downloaded."
			fi
		
			writeyellow "Extracting atlassian-servicedesk-$VERSION.tar.gz archive to atlassian-jira-servicedesk-$VERSION-standalone"
			tar xzf atlassian-servicedesk-$VERSION.tar.gz

			writeyellow "Deleting atlassian-servicedesk-$VERSION.tar.gz archive"
			rm atlassian-servicedesk-$VERSION.tar.gz

			writeyellow "Renaming directory atlassian-jira-servicedesk-$VERSION-standalone to $VERSION"
			mv atlassian-jira-servicedesk-$VERSION-standalone $VERSION

			writeyellow "Creating JIRA_HOME directory at $HOME/atlassian/data/$PRODUCT/$VERSION"
			mkdir -p $HOME/atlassian/data/$PRODUCT/$VERSION
		
			# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
			# JIRA_HOME is hardcoded at $HOME/atlassian/apps/$PRODUCT/$VERSION/atlassian-jira/WEB-INF/classes/jira-application.properties #
			# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
			
			writeyellow "Configuring JIRA_HOME at jira-application.properties"
		
			echo "jira.home=$HOME/atlassian/data/$PRODUCT/$VERSION" >> $HOME/atlassian/apps/$PRODUCT/$VERSION/atlassian-jira/WEB-INF/classes/jira-application.properties
		
			if [ ! -z "$DBTYPE" ] ; then
				if [ $DBTYPE = "mysql" ]; then
					
					prepareMysqlDatabase "${PRODUCT//-}" $VERSION/lib
			
				elif [ $DBTYPE = "postgresql" ]; then
					
					preparePostgresqlDatabase "${PRODUCT//-}"
					
				fi	
			fi
		
			writeyellow "JIRA Service Desk $VERSION installation finished!"
			
			exec $ATL jira-servicedesk $VERSION start
		
		else
			writeyellow "JIRA Service Desk $VERSION is already installed. Installation will end so as to avoid overwriting."
		fi
	elif [ $EXECUTION = "start" ]; then
		
		if verifyExisting $PRODUCT $VERSION; then
			
			if ! isListeningOn 8080; then
				writeyellow "\nStarting JIRA Service Desk $VERSION\n"
				$HOME/atlassian/apps/$PRODUCT/$VERSION/bin/start-jira.sh
			else
				writeyellow "\nJIRA Service Desk $VERSION is already running\n"
			fi
			
			JiraShowLog $PRODUCT $VERSION
		fi
	elif [ $EXECUTION = "stop" ]; then
		
		if verifyExisting $PRODUCT $VERSION; then
			if isListeningOn 8080; then
				writeyellow "\nStopping JIRA Service Desk $VERSION\n"
				$HOME/atlassian/apps/$PRODUCT/$VERSION/bin/stop-jira.sh
			else
				writeyellow "\nJIRA Service Desk $VERSION is not running\n"
			fi
		fi
	elif [ $EXECUTION = "restart" ]; then
		
		if verifyExisting $PRODUCT $VERSION; then
			if isListeningOn 8080; then
				writeyellow "\nStopping JIRA Service Desk $VERSION\n"
				$HOME/atlassian/apps/$PRODUCT/$VERSION/bin/stop-jira.sh
			else
				writeyellow "\nJIRA Service Desk $VERSION is not running\n"
			fi
						
			writeyellow "\nStarting JIRA Service Desk $VERSION\n"
			$HOME/atlassian/apps/$PRODUCT/$VERSION/bin/start-jira.sh
			JiraShowLog $PRODUCT $VERSION
		fi
	else 
		writeyellow "Invalid execution type specified. Valid params are 'install', 'start', 'stop' and 'restart'."
	fi
elif [ $PRODUCT = "confluence" ]; then
	
	if [ $EXECUTION = "install" ]; then
		if [ ! -d "$HOME/atlassian/apps/$PRODUCT" ]; then
			mkdir -p $HOME/atlassian/apps/$PRODUCT
		fi
	
		cd $HOME/atlassian/apps/$PRODUCT
	
		# Verify if the directory of the version being installed doesn't already exist. If it does, do not proceed to avoid overwriting
		if [ ! -d $VERSION ]; then
			
			writeyellow "Confluence Server $VERSION installation starting!"
		
			# If that directory does not exist, verify if the archive has already been downloaded
			if [ ! -f "atlassian-confluence-$VERSION.tar.gz" ]; then
				# If the archive has not been downloaded yet, verify if the version specified exists
				writeyellow "Validating version specified"
				if [[ `wget -S --spider https://www.atlassian.com/software/confluence/downloads/binary/atlassian-confluence-$VERSION.tar.gz  2>&1 | grep 'HTTP/1.1 200 OK'` ]]; then
					# If the version specified exists, download it
					writeyellow "Version has been validated. Downloading atlassian-confluence-$VERSION.tar.gz archive. Please wait..."
					wget -q https://www.atlassian.com/software/confluence/downloads/binary/atlassian-confluence-$VERSION.tar.gz
				else
					writeyellow "Invalid version specified. Installation could not proceed."
					exit 1
				fi
			else
				writeyellow "Confluence Server $VERSION archive has been previously downloaded."
			fi
		
			writeyellow "Extracting atlassian-confluence-$VERSION.tar.gz archive to atlassian-confluence-$VERSION"
			tar xzf atlassian-confluence-$VERSION.tar.gz

			writeyellow "Deleting atlassian-confluence-$VERSION.tar.gz archive"
			rm atlassian-confluence-$VERSION.tar.gz

			writeyellow "Renaming directory atlassian-confluence-$VERSION to $VERSION"
			mv atlassian-confluence-$VERSION $VERSION

			writeyellow "Creating CONFLUENCE_HOME directory at $HOME/atlassian/data/$PRODUCT/$VERSION"
			mkdir -p $HOME/atlassian/data/$PRODUCT/$VERSION
		
			# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
			# CONFLUENCE_HOME is hardcoded at $HOME/atlassian/apps/confluence/$VERSION/confluence/WEB-INF/classes/confluence-init.properties #
			# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
			
			writeyellow "Configuring CONFLUENCE_HOME at confluence-init.properties"
			
			rm $HOME/atlassian/apps/$PRODUCT/$VERSION/confluence/WEB-INF/classes/confluence-init.properties
			echo "confluence.home=$HOME/atlassian/data/$PRODUCT/$VERSION" > $HOME/atlassian/apps/$PRODUCT/$VERSION/confluence/WEB-INF/classes/confluence-init.properties
		
			if [ ! -z "$DBTYPE" ] ; then
				if [ $DBTYPE = "mysql" ]; then
					
					prepareMysqlDatabase $PRODUCT $VERSION/confluence/WEB-INF/lib
			
				elif [ $DBTYPE = "postgresql" ]; then
					
					preparePostgresqlDatabase $PRODUCT
					
				fi	
			fi
		
			writeyellow "Confluence Server $VERSION installation finished!"
			
			exec $ATL confluence $VERSION start
		
		else
			writeyellow "Confluence Server $VERSION is already installed. Installation will end so as to avoid overwriting."
		fi
	elif [ $EXECUTION = "start" ]; then
		
		if verifyExisting $PRODUCT $VERSION; then
			
			if ! isListeningOn 8090; then
				writeyellow "\nStarting Confluence Server $VERSION\n"
				$HOME/atlassian/apps/$PRODUCT/$VERSION/bin/start-confluence.sh
			else
				writeyellow "\nConfluence Server $VERSION is already running\n"
			fi
			
			ConfluenceShowLog $VERSION
		fi
	elif [ $EXECUTION = "stop" ]; then
		
		if verifyExisting $PRODUCT $VERSION; then
			if isListeningOn 8090; then
				writeyellow "\nStopping Confluence Server $VERSION\n"
				$HOME/atlassian/apps/$PRODUCT/$VERSION/bin/stop-confluence.sh
			else
				writeyellow "\nConfluence Server $VERSION is not running\n"
			fi
		fi
	elif [ $EXECUTION = "restart" ]; then
		
		if verifyExisting $PRODUCT $VERSION; then
			if isListeningOn 8090; then
				writeyellow "\nStopping Confluence Server $VERSION\n"
				$HOME/atlassian/apps/$PRODUCT/$VERSION/bin/stop-confluence.sh
			else
				writeyellow "\nConfluence Server $VERSION is not running\n"
			fi
						
			writeyellow "\nStarting Confluence Server $VERSION\n"
			$HOME/atlassian/apps/$PRODUCT/$VERSION/bin/start-confluence.sh
			ConfluenceShowLog $VERSION
		fi
	else 
		writeyellow "Invalid execution type specified. Valid params are 'install', 'start', 'stop' and 'restart'."
	fi
fi