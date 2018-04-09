#!/bin/bash

unsuccessful_exit()
{
  echo "FATAL: Exiting script due to: $1. Exit code: $2";
  exit $2;
}

NODE_TYPE=$1  # ca, orderer, peer
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
AZURE_PREFIX=${13}
FABRIC_VERSION=x86_64-1.1.0

# TODO: extract those from the configuration
PEER_ORG_DOMAIN="org1.fabienpe.com"
ORDERER_ORG_DOMAIN="fabienpe.com"

echo "Configuring node:"
echo "  NODE_TYPE="${NODE_TYPE}
echo "  AZUREUSER="${AZUREUSER}
echo "  ARTIFACTS_URL_PREFIX="${ARTIFACTS_URL_PREFIX}
echo "  NODE_INDEX="${NODE_INDEX}
echo "  CA_PREFIX="${CA_PREFIX}
echo "  CA_NUM="${CA_NUM}
echo "  ORDERER_PREFIX="${ORDERER_PREFIX}
echo "  ORDERER_NUM="${ORDERER_NUM}
echo "  PEER_PREFIX="${PEER_PREFIX}
echo "  PEER_NUM="${PEER_NUM}
echo "  CA_USER="${CA_USER}
echo "  CA_PASSWORD="${CA_PASSWORD}
echo "  AZURE_PREFIX="${AZURE_PREFIX}
echo "  FABRIC_VERSION="${FABRIC_VERSION}
echo "  PEER_ORG_DOMAIN="${PEER_ORG_DOMAIN}
echo "  ORDERER_ORG_DOMAIN="${ORDERER_ORG_DOMAIN}


function generate_artifacts {
    echo "############################################################"
    echo "Generating network artifacts..."

    # Retrieve configuration templates
    wget -N ${ARTIFACTS_URL_PREFIX}/configtx_template.yaml
    wget -N ${ARTIFACTS_URL_PREFIX}/crypto-config_template.yaml

    # Retrieve binaries
    curl -qL https://nexus.hyperledger.org/content/repositories/releases/org/hyperledger/fabric/hyperledger-fabric/linux-amd64-1.1.0/hyperledger-fabric-linux-amd64-1.1.0.tar.gz -o hyperledger-fabric-linux-amd64-1.1.0.tar.gz
    tar -xvf hyperledger-fabric-linux-amd64-1.1.0.tar.gz || unsuccessful_exit "Failed to retrieve binaries" 212

    # Set up environment
    os_arch=$(echo "$(uname -s)-amd64" | awk '{print tolower($0)}')
    export FABRIC_CFG_PATH=$PWD

    # Parse configuration templates
    sed -e "s/{{PREFIX}}/${AZURE_PREFIX}/g" -e "s/{{PEER_NUM}}/${PEER_NUM}/g" crypto-config_template.yaml > crypto-config.yaml
    sed -e "s/{{PREFIX}}/${AZURE_PREFIX}/g" configtx_template.yaml > configtx.yaml

    if [ -d $HOME/crypto-config ]; then # TODO: Do the test for each file
        rm -rf $HOME/crypto-config;
    fi;

    # Generate crypto config
    ./bin/cryptogen generate --config=./crypto-config.yaml || unsuccessful_exit "Failed to generate crypto config" 213

    # Generate genesis block
    ./bin/configtxgen -profile ComposerOrdererGenesis -outputBlock orderer.block || unsuccessful_exit "Failed to generate orderer genesis block" 214

    # Generate transaction configuration
    ./bin/configtxgen -profile ComposerChannel -outputCreateChannelTx composerchannel.tx -channelID composerchannel || unsuccessful_exit "Failed to generate transaction channel" 215

    # Generate anchor peer update for Org1MSP
    ./bin/configtxgen -profile ComposerChannel -outputAnchorPeersUpdate Org1MSPanchors.tx -channelID composerchannel -asOrg Org1 || unsuccessful_exit "Failed to generate anchor peer update for Org1" 216
}

function get_artifacts {
    echo "############################################################"
    echo "Retrieving network artifacts..."

    # Copy the artifacts from the first CA host
    scp -o StrictHostKeyChecking=no "${CA_PREFIX}0:~/configtx.yaml" . || unsuccessful_exit "Failed to retrieve configtx.yaml" 217
    scp -o StrictHostKeyChecking=no "${CA_PREFIX}0:~/orderer.block" . || unsuccessful_exit "Failed to retrieve orderer.block" 218
    scp -o StrictHostKeyChecking=no "${CA_PREFIX}0:~/composerchannel.tx" . || unsuccessful_exit "Failed to retrieve composerchannel.tx" 219
    scp -o StrictHostKeyChecking=no -r "${CA_PREFIX}0:~/crypto-config" .  || unsuccessful_exit "Failed to retrieve crypto-config" 220
    
    echo "############################################################"
}

function distribute_ssh_key {
    echo "############################################################"
    echo "Generating ssh key..."

    # Generate new ssh key pair
    rm -f ~/.ssh/id_rsa && ssh-keygen -q -t rsa -N "" -f ~/.ssh/id_rsa || unsuccessful_exit "Failed to generate ssh key" 221

    # Authorize new key
    cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/authorized_keys

    # Expose private key to other nodes
    while true; do echo -e "HTTP/1.1 200 OK\n\n$(cat ~/.ssh/id_rsa)" | nc -l -p 1515; done &

    echo "############################################################"
}

function get_ssh_key {
    echo "############################################################"
    echo "Retrieving ssh key..."

    # Get the ssh key from the first CA host
    # TODO: loop here waiting for the request to succeed, instead of sequencing via the template dependencies?
    curl "http://${CA_PREFIX}0:1515/" -o ~/.ssh/id_rsa || unsuccessful_exit "Failed to retrieve ssh key" 222

    # Fix permissions
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/id_rsa

    echo "############################################################"
}

function install_composer {
    # Install composer and its prerequisites on the VM running Hyperledger CA
    echo "############################################################"
    echo "Installing composer development tools..."

    # Execute nvm installation script
    echo "# Executing nvm installation script"
    curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.2/install.sh | bash

    # Set up nvm environment without restarting the shell
    export NVM_DIR="${HOME}/.nvm"
    [ -s "${NVM_DIR}/nvm.sh" ] && . "${NVM_DIR}/nvm.sh"
    [ -s "${NVM_DIR}/bash_completion" ] && . "${NVM_DIR}/bash_completion"

    # Install nodeJS
    echo "# Installing nodeJS"
    nvm install --lts || unsuccessful_exit "Failed to install nodejs" 223

    # Configure nvm to use version 6.9.5
    nvm use --lts
    nvm alias default 'lts/*'

    # Install the latest version of npm
    echo "# Installing npm"
    npm install npm@latest -g

    # Log installation details for user
    echo -n 'Node:           '
    node --version
    echo -n 'npm:            '
    npm --version
    echo -n 'Docker:         '
    docker --version
    echo -n 'Python:         '
    python -V

    # Install development environment
    # https://hyperledger.github.io/composer/latest/installing/development-tools.html

    # Install CLI tools
    npm install -g composer-cli || unsuccessful_exit "Failed to install composer-cli" 224
    npm install -g composer-rest-server  || unsuccessful_exit "Failed to install composer-rest-server" 225
    npm install -g generator-hyperledger-composer  || unsuccessful_exit "Failed to install generator-hyperledger-composer" 226
    npm install -g yo  || unsuccessful_exit "Failed to install yo" 227

    echo "############################################################"
}

function prepare_tutorial {
    echo "############################################################"
    echo "Preparing tutorial script and parameters..."

    cd $HOME
    curl -qL ${ARTIFACTS_URL_PREFIX}/tutorial/run_tutorial_template.sh \
        -o run_tutorial_template.sh

    sed -e "s/{{PEER_ORG_DOMAIN}}/${PEER_ORG_DOMAIN}/g" \
        -e "s/{{CA_USER}}/${CA_USER}/g" \
        -e "s/{{CA_PASSWORD}}/${CA_PASSWORD}/g" \
        -e "s/{{PEER_PREFIX}}/${PEER_PREFIX}/g" \
        run_tutorial_template.sh > run_tutorial.sh

    chmod u+x run_tutorial.sh

    curl -qL ${ARTIFACTS_URL_PREFIX}/tutorial/tutorial-network.zip \
        -o $HOME/tutorial-network.zip

    cd $HOME
    unzip tutorial-network.zip
    cd tutorial-network

    sed -e "s/{{PEER_PREFIX}}/${PEER_PREFIX}/g" \
        -e "s/{{CA_PREFIX}}/${CA_PREFIX}/g" \
        -e "s/{{ORDERER_PREFIX}}/${ORDERER_PREFIX}/g" \
        -e "s/{{PEER_ORG_DOMAIN}}/${PEER_ORG_DOMAIN}/g" \
        -e "s/{{ORDERER_ORG_DOMAIN}}/${ORDERER_ORG_DOMAIN}/g" \
        connection_template.json > connection.json
    
    echo "############################################################"
}

function install_ca {
    echo "############################################################"
    echo "Installing Membership Service..."

    cacert="/etc/hyperledger/fabric-ca-server-config/ca.${PEER_ORG_DOMAIN}-cert.pem"
    cakey="/etc/hyperledger/fabric-ca-server-config/$(basename crypto-config/peerOrganizations/${PEER_ORG_DOMAIN}/ca/*_sk)"

    # Pull Docker image
    docker pull hyperledger/fabric-ca:${FABRIC_VERSION} || unsuccessful_exit "Failed to pull docker CA image" 213

    # Start CA
    docker run --name ${CA_PREFIX}0.${ORDERER_ORG_DOMAIN} -d --restart=always -p 7054:7054 \
        -e CORE_LOGGING_LEVEL=debug \
        -e FABRIC_CA_HOME=/etc/hyperledger/fabric-ca-server \
        -e FABRIC_CA_SERVER_CA_NAME=${CA_PREFIX}0.${PEER_ORG_DOMAIN} \
        -v $HOME/crypto-config/peerOrganizations/${PEER_ORG_DOMAIN}/ca/:/etc/hyperledger/fabric-ca-server-config \
        hyperledger/fabric-ca:${FABRIC_VERSION} \
        fabric-ca-server start --ca.certfile $cacert --ca.keyfile $cakey -b "${CA_USER}":"${CA_PASSWORD}" -d \
        || unsuccessful_exit "Failed to start CA" 227

    echo "############################################################"
}

function install_orderer {
    echo "############################################################"
    echo "Installing Orderer..."

    # Pull Docker image
    docker pull hyperledger/fabric-orderer:${FABRIC_VERSION}

    # Start Orderer
    docker run --name ${ORDERER_PREFIX}0.${ORDERER_ORG_DOMAIN} -d --restart=always -p 7050:7050 \
        -e ORDERER_GENERAL_LOGLEVEL=debug \
        -e ORDERER_GENERAL_LISTENADDRESS=0.0.0.0 \
        -e ORDERER_GENERAL_GENESISMETHOD=file \
        -e ORDERER_GENERAL_GENESISFILE=/etc/hyperledger/configtx/orderer.block \
        -e ORDERER_GENERAL_LOCALMSPID=OrdererMSP \
        -e ORDERER_GENERAL_LOCALMSPDIR=/etc/hyperledger/msp/orderer/msp \
        -v $HOME/:/etc/hyperledger/configtx \
        -v $HOME/crypto-config/ordererOrganizations/${ORDERER_ORG_DOMAIN}/orderers/${ORDERER_PREFIX}0.${ORDERER_ORG_DOMAIN}/msp:/etc/hyperledger/msp/orderer/msp \
        hyperledger/fabric-orderer:${FABRIC_VERSION} orderer || unsuccessful_exit "Failed to start orderer" 228

    echo "############################################################"
}

function install_peer {
    echo "############################################################"
    echo "Installing Peer..."
    date

    # Pull Docker image
    docker pull hyperledger/fabric-peer:${FABRIC_VERSION}

    # The Peer needs this image to cerate chaincode containers
    docker pull hyperledger/fabric-ccenv:${FABRIC_VERSION}

    # Start Peer
    docker run --name ${PEER_PREFIX}${NODE_INDEX}.${PEER_ORG_DOMAIN} -d --restart=always -p 7051:7051 -p 7053:7053 \
        -e CORE_LOGGING_LEVEL=debug \
        -e CORE_VM_ENDPOINT=unix:///host/var/run/docker.sock \
        -e CORE_PEER_ID=${PEER_PREFIX}${NODE_INDEX}.${PEER_ORG_DOMAIN} \
        -e CORE_PEER_LOCALMSPID=Org1MSP \
        -e CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/peer/msp \
        -v /var/run:/host/var/run \
        -v $HOME/:/etc/hyperledger/configtx \
        -v $HOME/crypto-config/peerOrganizations/${PEER_ORG_DOMAIN}/peers/${PEER_PREFIX}${NODE_INDEX}.${PEER_ORG_DOMAIN}/msp:/etc/hyperledger/peer/msp \
        -v $HOME/crypto-config/peerOrganizations/${PEER_ORG_DOMAIN}/users:/etc/hyperledger/msp/users \
        hyperledger/fabric-peer:${FABRIC_VERSION} peer node start || unsuccessful_exit "Failed to start peer" 229

    # Commands to execute on one of the peers
    echo ${PEER_PREFIX}${NODE_INDEX}" started"
    if [ ${NODE_INDEX} -eq 0 ]; then
        echo "Creating channel..."
        echo "# Waiting 10 minutes."
        sleep 10m

        docker run -d --name CLI -v $HOME/crypto-config:/crypto-config \
            -v $HOME/composerchannel.tx:/composerchannel.tx \
            hyperledger/fabric-peer:x86_64-1.1.0;
        
        # docker exec CLI bash -c '<COMMAND 1> ; <COMMAND 2>'
        docker exec CLI bash -c 'export CORE_PEER_ADDRESS="'${PEER_PREFIX}'0:7051"; \
            export CORE_PEER_LOCALMSPID="Org1MSP"; \
            export CORE_PEER_MSPCONFIGPATH=/crypto-config/peerOrganizations/'${PEER_ORG_DOMAIN}'/users/Admin@'${PEER_ORG_DOMAIN}'/msp; \
            peer channel create -o '${ORDERER_PREFIX}'0:7050 -c composerchannel -f composerchannel.tx' \
            || unsuccessful_exit "Failed to create channel" 230;
        
        docker exec CLI bash -c 'export CORE_PEER_ADDRESS="'${PEER_PREFIX}'0:7051"; \
            export CORE_PEER_LOCALMSPID="Org1MSP"; \
            export CORE_PEER_MSPCONFIGPATH=/crypto-config/peerOrganizations/'${PEER_ORG_DOMAIN}'/users/Admin@'${PEER_ORG_DOMAIN}'/msp; \
            peer channel join -b composerchannel.block' \
            || unsuccessful_exit "Failed to join channel (${PEER_PREFIX}0)" 231;
        
        docker exec CLI bash -c 'export CORE_PEER_ADDRESS='${PEER_PREFIX}'1:7051; \
            export CORE_PEER_LOCALMSPID="Org1MSP"; \
            export CORE_PEER_MSPCONFIGPATH=/crypto-config/peerOrganizations/'${PEER_ORG_DOMAIN}'/users/Admin@'${PEER_ORG_DOMAIN}'/msp; \
            peer channel join -b composerchannel.block -o '${ORDERER_PREFIX}'0:7050'\
            || unsuccessful_exit "Failed to join channel (${PEER_PREFIX}1)" 232;
    fi

    echo "############################################################"
}


# Jump to node-specific steps

case "${NODE_TYPE}" in
"ca")
    generate_artifacts  
    distribute_ssh_key
    install_ca
    install_composer
    prepare_tutorial
    ;;
"orderer")
    get_ssh_key
    get_artifacts
    install_orderer
    ;;
"peer")
    get_ssh_key
    get_artifacts
    install_peer
    ;;
*)
	unsuccessful_exit "Invalid node type, exiting." 233
	exit 233
    ;;
esac
