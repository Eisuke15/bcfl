// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FederatedLearning is ERC20 {
    uint public MinWorkerNum; // The threshold of the number of workers

    uint public WorkerWithSRNum; // The number of workers with submission right. This value should be larger.
    uint public VotableModelNum; // The number of models that can be voted. This value should be larger.
    // Sum of WorkerWithSRNum and VotableModelNum must be far less than MinWorkerNum.

    uint public VoteNum; // The number of votes that a worker can put.

    string public initialModelCID; // The CID of the initial model.

    struct Worker {
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
    mapping(address => Worker) public workerInfo;
    Model[] public models; // The list of submitted models.

    mapping(string => bool) public existingModelCIDs; // The mapping of existing model CIDs.

    event LearningRightGranted(address indexed worker, uint indexed latestModelIndex);

    constructor(
        string memory _initialModelCID,
        uint _MinWorkerNum,
        uint _WorkerWithSRNum,
        uint _VotableModelNum,
        uint _VoteNum
        ) ERC20("Federated Learning Token", "FLT") {
        initialModelCID = _initialModelCID;
        MinWorkerNum = _MinWorkerNum;
        WorkerWithSRNum = _WorkerWithSRNum;
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
            grantLearningRightsToEligibleWorkersRandomly();
        }
    }

    // @notice Submit a new model and vote for existing models.
    // @dev Time complexity: O(workers.length + VoteNum * VotableModelNum)
    // @param _newModelCID The CID of the new model submitted by worker.
    // @param _votedModelCIDs The CIDs of the models voted by worker.
    function submitModel(string calldata _newModelCID, string[] calldata _votedModelCIDs) external {
        require(workers.length >= MinWorkerNum, "Not enough workers");
        Worker storage worker = workerInfo[msg.sender];
        require(worker.hasLearningRight, "No submission right");
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
        grantLearningRightsToEligibleWorkersRandomly();
    }

    // @notice Grant study rights to workers who have not yet acquired study rights until the total number of workers reaches the specified number.
    // @dev Time complexity (first): O(MinWorkerNum^2)
    // @dev Time complexity (after first):  O(workers.length + VotableModelNum)
    function grantLearningRightsToEligibleWorkersRandomly() private {
        uint[] memory eligibleWorkerIndices = getEligibleWorkerIndices();
        uint _workerWithSRNum = countWorkersWithRight();

        require(eligibleWorkerIndices.length >= WorkerWithSRNum - _workerWithSRNum, "Not enough eligible workers");

        uint nonce = 0;
        while (_workerWithSRNum < WorkerWithSRNum) {
            uint selectedWorkerIndex = eligibleWorkerIndices[random(eligibleWorkerIndices.length, nonce++)];
            Worker storage worker = workerInfo[workers[selectedWorkerIndex]];
            worker.hasLearningRight = true;
            worker.latestModelIndex = models.length;
            emit LearningRightGranted(workers[selectedWorkerIndex], models.length);
            _workerWithSRNum++;
            
            eligibleWorkerIndices = getEligibleWorkerIndices();
        }
    }

    // @notice Count the number of workers with submission right.
    // @dev Time complexity: O(worker.length)
    function countWorkersWithRight() private view returns (uint) {
        uint numWorkersWithRight = 0;
        for (uint i = 0; i < workers.length; i++) {
            if (workerInfo[workers[i]].hasLearningRight) {
                numWorkersWithRight++;
            }
        }
        return numWorkersWithRight;
    }

    // @notice Revoke the submission right of the worker who got submission right the earliest.
    // @dev Time complexity: O(worker.length)
    function revokeOldestLearningRight() private {
        uint oldestModelIndex = models.length;
        address oldestWorkerAddress;
        for (uint i = 0; i < workers.length; i++) {
            Worker storage worker = workerInfo[workers[i]];
            if (worker.hasLearningRight && worker.latestModelIndex < oldestModelIndex) {
                oldestModelIndex = worker.latestModelIndex;
                oldestWorkerAddress = workers[i];
            }
        }
        workerInfo[oldestWorkerAddress].hasLearningRight = false;
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

    // @notice Get the indices of workers who have not yet acquired submission right nor submitted a model recently. 
    // @dev Time complexity: O(workers.length + VotableModelNum)
    function getEligibleWorkerIndices() private view returns (uint[] memory) {
        bool[] memory isEligible = new bool[](workers.length);
        uint numEligibleWorkers = workers.length;
        for (uint i = 0; i < workers.length; i++) {
            isEligible[i] = !workerInfo[workers[i]].hasLearningRight;
            // decrement numEligibleWorkers if the worker is not eligible
            numEligibleWorkers -= isEligible[i] ? 0 : 1;
        }

        for (uint i = models.length; i > 0 && (models.length > VotableModelNum && i > models.length - VotableModelNum); i--) {
            // decrement numEligibleWorkers if the worker is still eligible
            numEligibleWorkers -= isEligible[models[i - 1].authorIndex] ? 1 : 0;
            isEligible[models[i - 1].authorIndex] = false;
        }

        // return indices where isEligible is true
        uint[] memory eligibleWorkerIndices = new uint[](numEligibleWorkers);
        uint index = 0;
        for (uint i = 0; i < workers.length; i++) {
            if (isEligible[i]) {
                eligibleWorkerIndices[index++] = i;
            }
        }

        return eligibleWorkerIndices;
    }
}

