#!/bin/bash

unsuccessful_exit()
{
  echo "FATAL: Exiting script due to: $1. Exit code: $2";
  exit $2;
}

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

FABRIC_VERSION=x86_64-1.0.1

# TODO: extract those from the configuration
PEER_ORG_DOMAIN="org1.example.com"
ORDERER_ORG_DOMAIN="example.com"

function generate_artifacts {
    echo "Generating network artifacts..."

    # Retrieve configuration templates
    wget -N ${ARTIFACTS_URL_PREFIX}/configtx_template.yaml
    wget -N ${ARTIFACTS_URL_PREFIX}/crypto-config_template.yaml

    # Retrieve binaries
    curl -qL https://nexus.hyperledger.org/content/repositories/releases/org/hyperledger/fabric/hyperledger-fabric/linux-amd64-1.0.1/hyperledger-fabric-linux-amd64-1.0.1.tar.gz -o hyperledger-fabric-linux-amd64-1.0.1.tar.gz 
    tar -xvf hyperledger-fabric-linux-amd64-1.0.1.tar.gz || unsuccessful_exit "Failed to retrieve binaries" 203

    # Set up environment
    os_arch=$(echo "$(uname -s)-amd64" | awk '{print tolower($0)}')
    export FABRIC_CFG_PATH=$PWD

    # Parse configuration templates
    sed -e "s/{{PREFIX}}/${PREFIX}/g" -e "s/{{PEER_NUM}}/${PEER_NUM}/g" crypto-config_template.yaml > crypto-config.yaml
    sed -e "s/{{PREFIX}}/${PREFIX}/g" configtx_template.yaml > configtx.yaml

    # Generate crypto config
    ./bin/cryptogen generate --config=./crypto-config.yaml || unsuccessful_exit "Failed to generate crypto config" 204

    # Generate genesis block
    ./bin/configtxgen -profile SampleOrgGenesis -outputBlock orderer.block || unsuccessful_exit "Failed to generate orderer genesis block" 205

    # Generate transaction configuration
    ./bin/configtxgen -profile SampleOrgChannel -outputCreateChannelTx channel.tx -channelID mychannel || unsuccessful_exit "Failed to generate transaction channel" 206

    # Generate anchor peer update for Org1MSP
    ./bin/configtxgen -profile SampleOrgChannel -outputAnchorPeersUpdate Org1MSPanchors.tx -channelID mychannel -asOrg Org1MSP || unsuccessful_exit "Failed to generate anchor peer update for Org1MSP" 207
}

function get_artifacts {
    echo "Retrieving network artifacts..."

    # Copy the artifacts from the first CA host
    scp -o StrictHostKeyChecking=no "${CA_PREFIX}0:~/configtx.yaml" . || unsuccessful_exit "Failed to retrieve configtx.yaml" 208
    scp -o StrictHostKeyChecking=no "${CA_PREFIX}0:~/orderer.block" . || unsuccessful_exit "Failed to retrieve orderer.block" 209
    scp -o StrictHostKeyChecking=no "${CA_PREFIX}0:~/channel.tx" . || unsuccessful_exit "Failed to retrieve channel.tx" 210
    scp -o StrictHostKeyChecking=no -r "${CA_PREFIX}0:~/crypto-config" .  || unsuccessful_exit "Failed to retrieve crypto-config" 211  
}

function distribute_ssh_key {
    echo "Generating ssh key..."

    # Generate new ssh key pair
    ssh-keygen -q -t rsa -N "" -f ~/.ssh/id_rsa || unsuccessful_exit "Failed to generate ssh key" 212

    # Authorize new key
    cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/authorized_keys

    # Expose private key to other nodes
    while true; do echo -e "HTTP/1.1 200 OK\n\n$(cat ~/.ssh/id_rsa)" | nc -l -p 1515; done &
}

function get_ssh_key {
    echo "Retrieving ssh key..."

    # Get the ssh key from the first CA host
    # TODO: loop here waiting for the request to succeed, instead of sequencing via the template dependencies?
    curl "http://${CA_PREFIX}0:1515/" -o ~/.ssh/id_rsa || unsuccessful_exit "Failed to retrieve ssh key" 201

    # Fix permissions
    chmod 700 ~/.ssh
    chmod 400 ~/.ssh/id_rsa
}

function install_ca {
    echo "Installing Membership Service..."

    cacert="/etc/hyperledger/fabric-ca-server-config/${PEER_ORG_DOMAIN}-cert.pem"
    cakey="/etc/hyperledger/fabric-ca-server-config/$(basename crypto-config/peerOrganizations/${PEER_ORG_DOMAIN}/ca/*_sk)"

    # Pull Docker image
    docker pull hyperledger/fabric-ca:${FABRIC_VERSION} || unsuccessful_exit "Failed to pull docker CA image" 213

    # Start CA
    docker run -d --restart=always -p 7054:7054 \
        -v $HOME/crypto-config/peerOrganizations/${PEER_ORG_DOMAIN}/ca:/etc/hyperledger/fabric-ca-server-config \
        hyperledger/fabric-ca:${FABRIC_VERSION} fabric-ca-server start --ca.certfile $cacert --ca.keyfile $cakey -b "${CA_USER}":"${CA_PASSWORD}" || unsuccessful_exit "Failed to start CA" 214
}

function install_orderer {
    echo "Installing Orderer..."

    # Pull Docker image
    docker pull hyperledger/fabric-orderer:${FABRIC_VERSION}

    # Start Orderer
    docker run -d --restart=always -p 7050:7050 \
        -e ORDERER_GENERAL_GENESISMETHOD=file \
        -e ORDERER_GENERAL_GENESISFILE=/var/hyperledger/orderer/orderer.block \
        -e ORDERER_GENERAL_LOCALMSPID=OrdererMSP \
        -e ORDERER_GENERAL_LOCALMSPDIR=/var/hyperledger/orderer/msp \
        -e ORDERER_GENERAL_LOGLEVEL=debug \
        -e ORDERER_GENERAL_LISTENADDRESS=0.0.0.0 \
        -v $HOME/configtx.yaml:/etc/hyperledger/fabric/configtx.yaml \
        -v $HOME/orderer.block:/var/hyperledger/orderer/orderer.block \
        -v $HOME/crypto-config/ordererOrganizations/${ORDERER_ORG_DOMAIN}/orderers/${ORDERER_PREFIX}0.${ORDERER_ORG_DOMAIN}/msp:/var/hyperledger/orderer/msp \
        hyperledger/fabric-orderer:${FABRIC_VERSION} orderer || unsuccessful_exit "Failed to start orderer" 215
}

function install_peer {
    echo "Installing Peer..."

    # Pull Docker image
    docker pull hyperledger/fabric-peer:${FABRIC_VERSION}

    # The Peer needs this image to cerate chaincode containers
    docker pull hyperledger/fabric-ccenv:${FABRIC_VERSION}

    # Start Peer
    docker run -d --restart=always -p 7051:7051 -p 7053:7053 \
        -e CORE_PEER_ID=${PEER_PREFIX}${NODE_INDEX}.${PEER_ORG_DOMAIN} \
        -e CORE_PEER_LOCALMSPID=Org1MSP \
        -e CORE_VM_ENDPOINT=unix:///host/var/run/docker.sock \
        -v /var/run:/host/var/run \
        -v $HOME/configtx.yaml:/etc/hyperledger/fabric/configtx.yaml \
        -v $HOME/crypto-config/peerOrganizations/${PEER_ORG_DOMAIN}/peers/${PEER_PREFIX}${NODE_INDEX}.${PEER_ORG_DOMAIN}/msp:/etc/hyperledger/fabric/msp \
        hyperledger/fabric-peer:${FABRIC_VERSION} peer node start --peer-defaultchain=false || unsuccessful_exit "Failed to start peer" 216
}


# Jump to node-specific steps

case "${NODE_TYPE}" in
"ca")
    generate_artifacts  
    distribute_ssh_key
    install_ca
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
	unsuccessful_exit "Invalid node type, exiting." 202
	exit 202
    ;;
esac
