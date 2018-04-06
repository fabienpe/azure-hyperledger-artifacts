# Hyperledger Fabric 1.1.0 and Composer 0.19 on Azure

This set of templates and scripts is based on the Microsoft [Microsoft Hyperledger Fabric on Azure solution template](https://azuremarketplace.microsoft.com/en-us/marketplace/apps/microsoft-azure-blockchain.azure-blockchain-hyperledger-fabric). It performs a deployment of Hyperledger Fabric 1.1.0 nodes and Hyperledger Composer 0.19.0.

After deployment you will have:

- 4 Ubuntu virtual machines, each running a docker container with a specific Hyperledger node: ca0, ordered0, peer0 and peer1.
- peer0 and peer1 will be part of the same channel, called composerchannel.
- Composer is installed on ca0 and there is a shell script `run_tutorial.sh` ready to be called in the root folder to reproduce the steps of the [Deploying a Hyperledger Composer blockchain business network to Hyperledger Fabric for a single organization](https://hyperledger.github.io/composer/latest/tutorials/deploy-to-fabric-single-org) tutorial.
- A business network called `tutorial-network` is deployed. It is the same as the one provided in [Developer tutorial for creating a Hyperledger Composer solution](https://hyperledger.github.io/composer/latest/tutorials/developer-tutorial).

## Usage

1. Download `template.json`, `parameters.json` and one of the Azure deployment scripts such as `deploy.sh` and save them in the same directory.
2. Edit the `parameters.json` file and change the value of `adminSSHKey` to the public key of the SSH key you use in your  Azure Cloud Shell. Apply other customisation.
3. From a shell, got to the directory where you saved the file (sep 1) and execute the deployment script.

The deployment takes approximately 30 minutes.