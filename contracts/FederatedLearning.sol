// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FederatedLearning is ERC20 {
    uint public ClientNumThres; // The threshold of the number of clients

    uint public ClientWithLearnigLightNum; // The number of clients with learning right. This value should be larger.
    uint public VotableModelNum; // The number of models that can be voted. This value should be larger.
    // Sum of ClientWithLearnigLightNum and VotableModelNum must be far less than ClientNumThres.

    uint public VoteNum; // The number of votes that a client can put.

    string public initialModelCID; // The CID of the initial model.

    struct Client {
        bool registered;
        bool hasLearningRight;
        uint latestModelIndex;
    }

    struct Model {
        string CID;
        address author;
    }

    address[] public clients; // The list of registered clients.
    mapping(address => Client) public clientInfo;
    Model[] public models; // The list of submitted models.

    event LearningRightGranted(address indexed client, uint indexed latestModelIndex);

    constructor(
        string memory _initialModelCID,
        uint _ClientNumThres,
        uint _ClientWithLearnigLightNum,
        uint _VotableModelNum,
        uint _VoteNum
        ) ERC20("Federated Learning Token", "FLT") {
        initialModelCID = _initialModelCID;
        ClientNumThres = _ClientNumThres;
        ClientWithLearnigLightNum = _ClientWithLearnigLightNum;
        VotableModelNum = _VotableModelNum;
        VoteNum = _VoteNum;
    }

    // Register as a client.
    function register() external {
        require(!clientInfo[msg.sender].registered, "Already registered");
        clientInfo[msg.sender].registered = true;
        clients.push(msg.sender);

        if (clients.length == ClientNumThres) {
            grantLearningRights();
        }
    }

    // Submit a new model and vote for existing models.
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

        revokeOldestLearningRight();
        grantLearningRights();
    }

    // Grant study rights to clients who have not yet acquired study rights until the total number of clients reaches the specified number.
    function grantLearningRights() private {
        address[] memory eligibleClients = getEligibleClients();
        uint numEligibleClients = eligibleClients.length;

        uint salt = 0;
        uint _clientWithRightNum = countClientsWithRight();
        while (_clientWithRightNum < ClientWithLearnigLightNum) {
            address selectedClientAddress = eligibleClients[random(numEligibleClients, salt++)];
            Client storage client = clientInfo[selectedClientAddress];

            if (!client.hasLearningRight) {
                client.hasLearningRight = true;
                client.latestModelIndex = models.length;
                emit LearningRightGranted(selectedClientAddress, models.length);
                _clientWithRightNum++;
            }
        }
    }

    // Count the number of clients with learning right.
    function countClientsWithRight() private view returns (uint) {
        uint numClientsWithRight = 0;
        for (uint i = 0; i < clients.length; i++) {
            if (clientInfo[clients[i]].hasLearningRight) {
                numClientsWithRight++;
            }
        }
        return numClientsWithRight;
    }

    // Revoke the learning right of the client who got learning right the earliest.
    function revokeOldestLearningRight() private {
        uint oldestModelIndex = models.length;
        address oldestClientAddress;
        for (uint i = 0; i < clients.length; i++) {
            Client storage client = clientInfo[clients[i]];
            if (client.hasLearningRight && client.latestModelIndex < oldestModelIndex) {
                oldestModelIndex = client.latestModelIndex;
                oldestClientAddress = clients[i];
            }
        }
        clientInfo[oldestClientAddress].hasLearningRight = false;
    }

    
    // calculate a random number between 0 and max - 1
    function random(uint max, uint counter) private view returns (uint) {
        return uint(keccak256(abi.encodePacked(block.timestamp, counter))) % max;
    }


    // Check if the model CID already exists in `models`.
    function modelExists(string memory _CID) private view returns (bool) {
        for (uint i = 0; i < models.length; i++) {
            if (keccak256(abi.encodePacked(models[i].CID)) == keccak256(abi.encodePacked(_CID))) {
                return true;
            }
        }
        return false;
    }

    // Convert the model CIDs to indices of `models`.
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

    // Validate the indices of the models that a client voted.
    function validateModelIndices(uint latestModelIndex, uint[] memory modelIndices) private view {
        uint _voteNum = latestModelIndex < VoteNum ? latestModelIndex : VoteNum;

        require(_voteNum == modelIndices.length, "Invalid number of vote"); // ここが機能してない
        if (modelIndices.length != 0) {
            for (uint i = 0; i < modelIndices.length; i++) {
                require(modelIndices[i] < latestModelIndex, "Invalid model index"); 
                require(modelIndices[i] >= (latestModelIndex > VotableModelNum ? latestModelIndex - VotableModelNum : 0), "Invalid model index");
            }
        }
    }

    // Get the addresses of the clients who are eligible to get learning right.
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


    // Check if a client is eligible to get learning right.
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

