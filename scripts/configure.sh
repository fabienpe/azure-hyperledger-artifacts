#!/bin/bash

# Utility function to exit with message
unsuccessful_exit()
{
  echo "FATAL: Exiting script due to: $1. Exit code: $2";
  exit $2;
}

#############
# Parameters
#############
# Validate that all arguments are supplied
if [ $# -lt 13 ]; then unsuccessful_exit "Insufficient parameters supplied. Exiting" 200; fi

NODE_TYPE=$1
AZUREUSER=$2
ARTIFACTS_URL_PREFIX=$3
NODE_INDEX=$4
CA_PREFIX=$5
CA_NUM=$6
ORDERER_PREFIX=$7
ORDERER_NUM=$8
PEER_PREFIX=$9
PEER_NUM=${10}
CA_USER=${11}
CA_PASSWORD=${12}
PREFIX=${13}

###########
# Constants
###########
HOMEDIR="/home/$AZUREUSER";
CONFIG_LOG_FILE_PATH="$HOMEDIR/config.log";

###########################################
# System packages to be installed as root #
###########################################

# Docker installation: https://docs.docker.com/engine/installation/linux/ubuntu/#install-using-the-repository

# Install packages to allow apt to use a repository over HTTPS:
apt-get -y install apt-transport-https ca-certificates curl software-properties-common \
	|| unsuccessful_exit "Unable to install packages that allow apt to use HTTPS" 200

# Add Docker’s official GPG key:
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - \
	|| unsuccessful_exit "Unable to install Docker's official GPG key" 201

# Set up the stable repository:
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
	|| unsuccessful_exit "Unable to setup Docker repository" 202

# Update the apt package index:
apt-get update || unsuccessful_exit "Unable to update apt package index" 203

# Install the latest version of Docker:
apt-get -y install docker-ce || unsuccessful_exit "Unable to install docker" 204

# Create the docker group:
groupadd docker

# Add the Azure user to the docker group:
usermod -aG docker $AZUREUSER

case "${NODE_TYPE}" in
"ca")
	# Update package lists
	apt-add-repository -y ppa:git-core/ppa
	apt-get update || unsuccessful_exit "Unable to update apt package index" 205

    # Install Unzip
	apt-get install unzip  || unsuccessful_exit "Unable to install unzip" 206

	# Install Git
	apt-get install -y git || unsuccessful_exit "Unable to install git" 207

	# Install nvm dependencies
	apt-get -y install build-essential libssl-dev || unsuccessful_exit "Unable to install nvm dependencies" 208

	# Install python v2 if required
	set +e
	COUNT="$(python -V 2>&1 | grep -c 2.)"
	if [ ${COUNT} -ne 1 ]
	then
   		apt-get install -y python-minimal || unsuccessful_exit "Unable to install python" 209
	fi
    ;;
esac


################################################
# System configuration to be performed as root #
################################################

curl -sL https://deb.nodesource.com/setup_8.x | bash
apt-get -y install nodejs build-essential || unsuccessful_exit "Unable to install nodejs" 210
npm install gulp -g || unsuccessful_exit "Unable to install gulp" 211

#############
# Get the script for running as Azure user
#############
cd "/home/$AZUREUSER";

sudo -u $AZUREUSER /bin/bash -c "wget -N ${ARTIFACTS_URL_PREFIX}/scripts/configure-fabric-azureuser.sh";

##################################
# Initiate loop for error checking
##################################
FAILED_EXITCODE=0
for LOOPCOUNT in `seq 1 5`; do
	sudo -u $AZUREUSER /bin/bash /home/$AZUREUSER/configure-fabric-azureuser.sh "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" "${12}" "${13}" "${14}" "${15}" "${16}" "${17}" "${18}" >> $CONFIG_LOG_FILE_PATH 2>&1;
	
	FAILED_EXITCODE=$?
	if [ $FAILED_EXITCODE -ne 0 ]; then
		echo "FAILED_EXITCODE: $FAILED_EXITCODE " >> $CONFIG_LOG_FILE_PATH;
		echo "Command failed on try $LOOPCOUNT, retrying..." >> $CONFIG_LOG_FILE_PATH;
		sleep 5;
		continue;
	else
		echo "======== Deployment successful! ======== " >> $CONFIG_LOG_FILE_PATH;
		exit 0;
	fi
done

echo "One or more commands failed after 5 tries. Deployment failed." >> $CONFIG_LOG_FILE_PATH;
unsuccessful_exit "One or more commands failed after 5 tries. Deployment failed." $FAILED_EXITCODE
