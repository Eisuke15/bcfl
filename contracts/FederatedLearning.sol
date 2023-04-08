// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FederatedLearning is ERC20 {
    uint public constant ClientNumThres = 10; // The threshold of the number of clients

    uint public constant ClientWithLearnigLightNum = 3; // The number of clients with learning right. This value should be larger.
    uint public constant VotableModelNum = 3; // The number of models that can be voted. This value should be larger.
    // Sum of ClientWithLearnigLightNum and VotableModelNum must be far less than ClientNumThres.

    uint public constant VoteNum = 1; // The number of votes that a client can put.
    string public initialModelCID;

    struct Client {
        bool registered;
        bool hasLearningRight;
        uint latestModelIndex;
    }

    struct Model {
        string CID;
        address author;
    }

    address[] public clients;
    mapping(address => Client) public clientInfo;
    Model[] public models;

    event LearningRightGranted(address indexed client, uint indexed modelIndex);

    constructor(string memory _initialModelCID) ERC20("Federated Learning Token", "FLT") {
        initialModelCID = _initialModelCID;
    }

    function register() external {
        require(!clientInfo[msg.sender].registered, "Already registered");
        clientInfo[msg.sender].registered = true;
        clients.push(msg.sender);

        if (clients.length == ClientNumThres) {
            grantLearningRights();
        }
    }

    function submitModel(string calldata _newModelCID, string[] calldata _votedModelCIDs) external {
        require(clients.length >= ClientNumThres, "Not enough clients");
        Client storage client = clientInfo[msg.sender];
        require(client.hasLearningRight, "No learning right");
        require(!modelExists(_newModelCID), "Model already exists");

        uint[] memory modelIndices = getModelIndices(_votedModelCIDs);
        validateModelIndices(client.latestModelIndex, modelIndices);

        models.push(Model(_newModelCID, msg.sender));
        client.hasLearningRight = false;

        for (uint i = 0; i < modelIndices.length; i++) {
            Model storage votedModel = models[modelIndices[i]];
            _mint(votedModel.author, 1);
        }

        updateLearningRights();
    }

    function grantLearningRights() private {
        uint salt = 0;
        uint clientWithRightNum = 0;
        while (clientWithRightNum < ClientWithLearnigLightNum) {
            address clientAddress = clients[random(clients.length, salt++)];
            Client storage client = clientInfo[clientAddress];

            if (!client.hasLearningRight) {
                client.hasLearningRight = true;
                client.latestModelIndex = models.length;
                emit LearningRightGranted(clientAddress, models.length);
                clientWithRightNum++;
            }
        }
    }

    
    // calculate a random number between 0 and max - 1
    function random(uint max, uint counter) private view returns (uint) {
        return uint(keccak256(abi.encodePacked(block.timestamp, counter))) % max;
    }


    function updateLearningRights() private {
        address[] memory eligibleClients = getEligibleClients();
        uint numEligibleClients = eligibleClients.length;

        uint counter = 0;
        if (numEligibleClients >= 2) {
            uint firstClientIndex = random(numEligibleClients, counter++);
            uint secondClientIndex;
            do {
                secondClientIndex = random(numEligibleClients, counter++);
            } while (secondClientIndex == firstClientIndex);
            
            grantLearningRightTo(eligibleClients[firstClientIndex]);
            grantLearningRightTo(eligibleClients[secondClientIndex]);
        }
    }


    function grantLearningRightTo(address clientAddress) private {
        Client storage client = clientInfo[clientAddress];
        client.hasLearningRight = true;
        client.latestModelIndex = models.length;
        emit LearningRightGranted(clientAddress, models.length);
    }

    function modelExists(string memory _CID) private view returns (bool) {
        for (uint i = 0; i < models.length; i++) {
            if (keccak256(abi.encodePacked(models[i].CID)) == keccak256(abi.encodePacked(_CID))) {
                return true;
            }
        }
        return false;
    }

    function getModelIndices(string[] memory _modelCIDs) private view returns (uint[] memory) {
        uint[] memory indices = new uint[](_modelCIDs.length);
        for (uint i = 0; i < _modelCIDs.length; i++) {
            for (uint j = 0; j < models.length; j++) {
                if (keccak256(abi.encodePacked(models[j].CID)) == keccak256(abi.encodePacked(_modelCIDs[i]))) {
                    indices[i] = j;
                    break;
                }
            }
        }
        return indices;
    }

    function validateModelIndices(uint latestModelIndex, uint[] memory modelIndices) private pure {
        uint _voteNum = latestModelIndex < VoteNum ? latestModelIndex : VoteNum;

        require(_voteNum == modelIndices.length, "Invalid number of vote");
        if (modelIndices.length != 0) {
            for (uint i = 0; i < modelIndices.length; i++) {
                require(modelIndices[i] < latestModelIndex, "Invalid model index"); 
                require(modelIndices[i] >= latestModelIndex - VotableModelNum, "Invalid model index");
            }
        }
    }

    function getEligibleClients() private view returns (address[] memory) {
        address[] memory tempEligibleClients = new address[](clients.length);
        uint numEligibleClients = 0;

        for (uint i = 0; i < clients.length; i++) {
            if (isClientEligible(clients[i])) {
                tempEligibleClients[numEligibleClients++] = clients[i];
            }
        }

        address[] memory eligibleClients = new address[](numEligibleClients);
        for (uint i = 0; i < numEligibleClients; i++) {
            eligibleClients[i] = tempEligibleClients[i];
        }

        return eligibleClients;
    }


    function isClientEligible(address clientAddress) private view returns (bool) {
        Client storage client = clientInfo[clientAddress];
        if (client.hasLearningRight || !client.registered) {
            return false;
        }

        for (uint i = models.length; i > 0 && (models.length > VotableModelNum && i > models.length - VotableModelNum); i--) {
            if (models[i - 1].author == clientAddress) {
                return false;
            }
        }

        return true;
    }
}

