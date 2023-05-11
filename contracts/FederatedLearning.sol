// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FederatedLearning is ERC20 {
    uint public MinWorkerNum; // The threshold of the number of workers

    uint public WorkerWithLRNum; // The number of workers with learning right. This value should be larger.
    uint public VotableModelNum; // The number of models that can be voted. This value should be larger.
    // Sum of WorkerWithLRNum and VotableModelNum must be far less than MinWorkerNum.

    uint public VoteNum; // The number of votes that a worker can put.

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

    address[] public workers; // The list of registered workers.
    mapping(address => Client) public workerInfo;
    Model[] public models; // The list of submitted models.

    mapping(string => bool) public existingModelCIDs; // The mapping of existing model CIDs.

    event LearningRightGranted(address indexed worker, uint indexed latestModelIndex);

    constructor(
        string memory _initialModelCID,
        uint _MinWorkerNum,
        uint _WorkerWithLRNum,
        uint _VotableModelNum,
        uint _VoteNum
        ) ERC20("Federated Learning Token", "FLT") {
        initialModelCID = _initialModelCID;
        MinWorkerNum = _MinWorkerNum;
        WorkerWithLRNum = _WorkerWithLRNum;
        VotableModelNum = _VotableModelNum;
        VoteNum = _VoteNum;
    }

    // @notice Register submitter as a worker.
    function register() external {
        require(!workerInfo[msg.sender].registered, "Already registered");
        workerInfo[msg.sender].registered = true;
        workerInfo[msg.sender].index = workers.length;
        workers.push(msg.sender);

        if (workers.length == MinWorkerNum) {
            grantLearningRights();
        }
    }

    // @notice Submit a new model and vote for existing models.
    // @dev Time complexity: O(workers.length + VoteNum * VotableModelNum)
    // @param _newModelCID The CID of the new model submitted by worker.
    // @param _votedModelCIDs The CIDs of the models voted by worker.
    function submitModel(string calldata _newModelCID, string[] calldata _votedModelCIDs) external {
        require(workers.length >= MinWorkerNum, "Not enough workers");
        Client storage worker = workerInfo[msg.sender];
        require(worker.hasLearningRight, "No learning right");
        require(!existingModelCIDs[_newModelCID], "Model already exists");

        uint[] memory modelIndices = getModelIndicesAndValidate(worker.latestModelIndex, _votedModelCIDs);

        models.push(Model(_newModelCID, worker.index));
        existingModelCIDs[_newModelCID] = true;
        worker.hasLearningRight = false;

        for (uint i = 0; i < modelIndices.length; i++) {
            Model storage votedModel = models[modelIndices[i]];
            _mint(workers[votedModel.authorIndex], 1);
        }

        revokeOldestLearningRight();
        grantLearningRights();
    }

    // @notice Grant study rights to workers who have not yet acquired study rights until the total number of workers reaches the specified number.
    // @dev Time complexity (first): O(MinWorkerNum^2)
    // @dev Time complexity (after first):  O(workers.length + VotableModelNum)
    function grantLearningRights() private {
        uint[] memory eligibleClientIndices = getEligibleClientIndices();
        uint _workerWithLRNum = countClientsWithRight();

        require(eligibleClientIndices.length >= WorkerWithLRNum - _workerWithLRNum, "Not enough eligible workers");

        uint nonce = 0;
        while (_workerWithLRNum < WorkerWithLRNum) {
            uint selectedClientIndex = eligibleClientIndices[random(eligibleClientIndices.length, nonce++)];
            Client storage worker = workerInfo[workers[selectedClientIndex]];
            worker.hasLearningRight = true;
            worker.latestModelIndex = models.length;
            emit LearningRightGranted(workers[selectedClientIndex], models.length);
            _workerWithLRNum++;
            
            eligibleClientIndices = getEligibleClientIndices();
        }
    }

    // @notice Count the number of workers with learning right.
    // @dev Time complexity: O(worker.length)
    function countClientsWithRight() private view returns (uint) {
        uint numClientsWithRight = 0;
        for (uint i = 0; i < workers.length; i++) {
            if (workerInfo[workers[i]].hasLearningRight) {
                numClientsWithRight++;
            }
        }
        return numClientsWithRight;
    }

    // @notice Revoke the learning right of the worker who got learning right the earliest.
    // @dev Time complexity: O(worker.length)
    function revokeOldestLearningRight() private {
        uint oldestModelIndex = models.length;
        address oldestClientAddress;
        for (uint i = 0; i < workers.length; i++) {
            Client storage worker = workerInfo[workers[i]];
            if (worker.hasLearningRight && worker.latestModelIndex < oldestModelIndex) {
                oldestModelIndex = worker.latestModelIndex;
                oldestClientAddress = workers[i];
            }
        }
        workerInfo[oldestClientAddress].hasLearningRight = false;
    }
    
    // @notice Calculate a random number between 0 and max - 1
    function random(uint max, uint nonce) private view returns (uint) {
        return uint(keccak256(abi.encodePacked(block.timestamp, nonce))) % max;
    }
    
    // @notice Convert model CIDs to indices. check if indices are valid at the same time.
    // @dev  Time complexity: O(VoteNum * VotableModelNum)
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

    // @notice Get the indices of workers who have not yet acquired learning right nor submitted a model recently. 
    // @dev Time complexity: O(workers.length + VotableModelNum)
    function getEligibleClientIndices() private view returns (uint[] memory) {
        bool[] memory isEligible = new bool[](workers.length);
        uint numEligibleClients = workers.length;
        for (uint i = 0; i < workers.length; i++) {
            isEligible[i] = !workerInfo[workers[i]].hasLearningRight;
            // decrement numEligibleClients if the worker is not eligible
            numEligibleClients -= isEligible[i] ? 0 : 1;
        }

        for (uint i = models.length; i > 0 && (models.length > VotableModelNum && i > models.length - VotableModelNum); i--) {
            // decrement numEligibleClients if the worker is still eligible
            numEligibleClients -= isEligible[models[i - 1].authorIndex] ? 1 : 0;
            isEligible[models[i - 1].authorIndex] = false;
        }

        // return indices where isEligible is true
        uint[] memory eligibleClientIndices = new uint[](numEligibleClients);
        uint index = 0;
        for (uint i = 0; i < workers.length; i++) {
            if (isEligible[i]) {
                eligibleClientIndices[index++] = i;
            }
        }

        return eligibleClientIndices;
    }
}

