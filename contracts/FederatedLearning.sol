// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FederatedLearning is ERC20 {
    uint public ClientNumThres; // The threshold of the number of clients

    uint public ClientWithLRNum; // The number of clients with learning right. This value should be larger.
    uint public VotableModelNum; // The number of models that can be voted. This value should be larger.
    // Sum of ClientWithLRNum and VotableModelNum must be far less than ClientNumThres.

    uint public VoteNum; // The number of votes that a client can put.

    string public initialModelCID; // The CID of the initial model.

    struct Client {
        uint index;
        bool registered;
        bool hasLearningRight;
        uint latestModelIndex;
    }

    struct Model {
        string CID;
        uint authorIndex;
    }

    address[] public clients; // The list of registered clients.
    mapping(address => Client) public clientInfo;
    Model[] public models; // The list of submitted models.

    mapping(string => bool) public existingModelCIDs; // The mapping of existing model CIDs.

    event LearningRightGranted(address indexed client, uint indexed latestModelIndex);

    constructor(
        string memory _initialModelCID,
        uint _ClientNumThres,
        uint _ClientWithLRNum,
        uint _VotableModelNum,
        uint _VoteNum
        ) ERC20("Federated Learning Token", "FLT") {
        initialModelCID = _initialModelCID;
        ClientNumThres = _ClientNumThres;
        ClientWithLRNum = _ClientWithLRNum;
        VotableModelNum = _VotableModelNum;
        VoteNum = _VoteNum;
    }

    // Register as a client.
    function register() external {
        require(!clientInfo[msg.sender].registered, "Already registered");
        clientInfo[msg.sender].registered = true;
        clientInfo[msg.sender].index = clients.length;
        clients.push(msg.sender);

        if (clients.length == ClientNumThres) {
            grantLearningRights();
        }
    }

    // Submit a new model and vote for existing models.
    // Time complexity: O(clients.length + VoteNum * VotableModelNum)
    function submitModel(string calldata _newModelCID, string[] calldata _votedModelCIDs) external {
        require(clients.length >= ClientNumThres, "Not enough clients");
        Client storage client = clientInfo[msg.sender];
        require(client.hasLearningRight, "No learning right");
        require(!existingModelCIDs[_newModelCID], "Model already exists");

        uint[] memory modelIndices = getModelIndicesAndValidate(client.latestModelIndex, _votedModelCIDs);

        models.push(Model(_newModelCID, client.index));
        existingModelCIDs[_newModelCID] = true;
        client.hasLearningRight = false;

        for (uint i = 0; i < modelIndices.length; i++) {
            Model storage votedModel = models[modelIndices[i]];
            _mint(clients[votedModel.authorIndex], 1);
        }

        revokeOldestLearningRight();
        grantLearningRights();
    }

    // Grant study rights to clients who have not yet acquired study rights until the total number of clients reaches the specified number.
    // Time complexity (first): O(ClientNumThres^2)
    // Time complexity (after first):  O(clients.length + VotableModelNum)
    function grantLearningRights() private {
        uint[] memory eligibleClientIndices = getEligibleClientIndices();
        uint _clientWithRightNum = countClientsWithRight();

        require(eligibleClientIndices.length >= ClientWithLRNum - _clientWithRightNum, "Not enough eligible clients");

        uint nonce = 0;
        while (_clientWithRightNum < ClientWithLRNum) {
            uint selectedClientIndex = eligibleClientIndices[random(eligibleClientIndices.length, nonce++)];
            Client storage client = clientInfo[clients[selectedClientIndex]];
            client.hasLearningRight = true;
            client.latestModelIndex = models.length;
            emit LearningRightGranted(clients[selectedClientIndex], models.length);
            _clientWithRightNum++;
            
            eligibleClientIndices = getEligibleClientIndices();
        }
    }

    // Count the number of clients with learning right.
    // Time complexity: O(client.length)
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
    // Time complexity: O(client.length)
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
    function random(uint max, uint nonce) private view returns (uint) {
        return uint(keccak256(abi.encodePacked(block.timestamp, nonce))) % max;
    }
    
    // convert model CIDs to indices. check if indices are valid at the same time.
    // Time complexity: O(VoteNum * VotableModelNum)
    function getModelIndicesAndValidate(uint latestModelIndex, string[] memory _modelCIDs) private view returns (uint[] memory) {
        uint[] memory indices = new uint[](_modelCIDs.length);
        uint _voteNum = latestModelIndex < VoteNum ? latestModelIndex : VoteNum;
        require(_voteNum == _modelCIDs.length, "Invalid number of vote");

        uint startModelIndex = latestModelIndex > VotableModelNum ? latestModelIndex - VotableModelNum : 0;

        for (uint i = 0; i < _modelCIDs.length; i++) {
            bool found = false;
            for (uint j = startModelIndex; j < latestModelIndex; j++) {
                if (keccak256(abi.encodePacked(models[j].CID)) == keccak256(abi.encodePacked(_modelCIDs[i]))) {
                    indices[i] = j;
                    found = true;
                    break;
                }
            }
            require(found, "Invalid model index");
        }
        return indices;
    }

    // Get the indices of clients who have not yet acquired learning right nor submitted a model recently. 
    // Time complexity: O(clients.length + VotableModelNum)
    function getEligibleClientIndices() private view returns (uint[] memory) {
        bool[] memory isEligible = new bool[](clients.length);
        uint numEligibleClients = clients.length;
        for (uint i = 0; i < clients.length; i++) {
            isEligible[i] = !clientInfo[clients[i]].hasLearningRight;
            // decrement numEligibleClients if the client is not eligible
            numEligibleClients -= isEligible[i] ? 0 : 1;
        }

        for (uint i = models.length; i > 0 && (models.length > VotableModelNum && i > models.length - VotableModelNum); i--) {
            // decrement numEligibleClients if the client is still eligible
            numEligibleClients -= isEligible[models[i - 1].authorIndex] ? 1 : 0;
            isEligible[models[i - 1].authorIndex] = false;
        }

        // return indices where isEligible is true
        uint[] memory eligibleClientIndices = new uint[](numEligibleClients);
        uint index = 0;
        for (uint i = 0; i < clients.length; i++) {
            if (isEligible[i]) {
                eligibleClientIndices[index++] = i;
            }
        }

        return eligibleClientIndices;
    }
}

