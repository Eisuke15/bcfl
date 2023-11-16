// test/FederatedLearning.test.js
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("FederatedLearning", function () {
  let FederatedLearning, federatedLearning, initialModelCID, alice, bob, charlie, david, eve, frank, george, hannah, ian, jane, kyle, lisa, workerNumThres, workerWithLearningRightNum, votableModelNum, voteNum;

  beforeEach(async () => {
    FederatedLearning = await ethers.getContractFactory("FederatedLearning");
    initialModelCID = "initialModelCID";
    workerNumThres = 10;
    workerWithLearningRightNum = 3;
    votableModelNum = 3;
    voteNum = 1;
    [alice, bob, charlie, david, eve, frank, george, hannah, ian, jane, kyle, lisa] = await ethers.getSigners();
    federatedLearning = await FederatedLearning.deploy(initialModelCID, workerNumThres, workerWithLearningRightNum, votableModelNum, voteNum);
  });

  describe("register", () => {
    it("should allow workers to register", async () => {
      await federatedLearning.connect(alice).register();
      expect((await federatedLearning.workerInfo(alice.address)).registered).to.equal(true);
    });

    it("should not allow workers to register twice", async () => {
      await federatedLearning.connect(alice).register();
      await expect(federatedLearning.connect(alice).register()).to.be.revertedWith("Already registered");
    });

    it("should grant submission rights when worker number reaches threshold", async () => {
      const workerPromises = [alice, bob, charlie, david, eve, frank, george, hannah, ian, jane].map((worker) =>
        federatedLearning.connect(worker).register()
      );
      await Promise.all(workerPromises);

      let numWorkersWithRight = 0;
      for (const worker of [alice, bob, charlie, david, eve, frank, george, hannah, ian, jane]) {
        const workerInfo = await federatedLearning.workerInfo(worker.address);
        if (workerInfo.hasLearningRight) {
          numWorkersWithRight++;
        }
      }
      expect(numWorkersWithRight).to.equal(3);
    });
  });

  describe("submitModel", () => {
    beforeEach(async () => {
      const workerPromises = [alice, bob, charlie, david, eve, frank, george, hannah, ian, jane].map((worker) =>
        federatedLearning.connect(worker).register()
      );
      await Promise.all(workerPromises);
    });

    it("should not allow submitting model without enough workers", async () => {
      const federatedLearning2 = await FederatedLearning.deploy(initialModelCID, workerNumThres, workerWithLearningRightNum, votableModelNum, voteNum);
      await federatedLearning2.connect(alice).register();
      await expect(federatedLearning2.connect(alice).submitModel("newModelCID", [])).to.be.revertedWith("Not enough workers");
    });

    it("should not allow submitting model without submission right", async () => {
      await expect(federatedLearning.connect(kyle).submitModel("newModelCID", [])).to.be.revertedWith("No submission right");
    });

    it("should not allow submitting an existing model", async () => {
      const workerWithLearningRight = await getWorkerWithLearningRight();
      await federatedLearning.connect(workerWithLearningRight).submitModel("newModelCID", []);
      const workerWithLearningRight2 = await getWorkerWithLearningRight();
      await expect(federatedLearning.connect(workerWithLearningRight2).submitModel("newModelCID", [])).to.be.revertedWith("Model already exists");
    });

    it("should allow submitting a new model and update submission rights", async () => {
      const workerWithLearningRight = await getWorkerWithLearningRight();
      await federatedLearning.connect(workerWithLearningRight).submitModel("newModelCID", []);
      
      // Check that the new model is added to the models array
      const model = await federatedLearning.models(0);
      const workerInfo = await federatedLearning.workerInfo(workerWithLearningRight.address);

      expect({
        CID: model.CID,
        authorIndex: model.authorIndex
      }).to.deep.equal({
        CID: "newModelCID",
        authorIndex: workerInfo.index,
      });

      // Check that the worker submitted the model has no submission right
      expect(workerInfo.hasLearningRight).to.equal(false);
      
      // Check that the worker with latest submission right has correct latestModelIndex
      const workerWithLatestLearningRight = await getWorkerWithLatestLearningRight();
      const workerInfoWithLatestLearningRight = await federatedLearning.workerInfo(workerWithLatestLearningRight.address);

      expect({
        registered: workerInfoWithLatestLearningRight.registered,
        hasLearningRight: workerInfoWithLatestLearningRight.hasLearningRight,
        latestModelIndex: Number(workerInfoWithLatestLearningRight.latestModelIndex),
      }).to.deep.equal({
        registered: true,
        hasLearningRight: true,
        latestModelIndex: 1,
      });
  
      let numWorkersWithRight = 0;
      for (const worker of [alice, bob, charlie, david, eve, frank, george, hannah, ian, jane]) {
        const workerInfo = await federatedLearning.workerInfo(worker.address);
        if (workerInfo.hasLearningRight) {
          numWorkersWithRight++;
        }
      }
      expect(numWorkersWithRight).to.equal(3);
    });
  

    it("should mint tokens for voted models", async () => {
      const worker = await getWorkerWithLearningRight();
      await federatedLearning.connect(worker).submitModel("newModelCID", []);
      const worker2 = await getWorkerWithLatestLearningRight();
      await federatedLearning.connect(worker2).submitModel("newModelCID2", ["newModelCID"]);

      expect(await federatedLearning.balanceOf(worker.address)).to.equal(1);
      expect(await federatedLearning.balanceOf(worker2.address)).to.equal(0);
    });
  });

  async function getWorkerWithLearningRight() {
    for (const worker of [alice, bob, charlie, david, eve, frank, george, hannah, ian, jane]) {
      const workerInfo = await federatedLearning.workerInfo(worker.address);
      if (workerInfo.hasLearningRight) {
        return worker;
      }
    }
  }

  async function getWorkerWithLatestLearningRight() {
    let workerWithLatestLearningRight;
    let latestModelIndex = 0;
    for (const worker of [alice, bob, charlie, david, eve, frank, george, hannah, ian, jane]) {
      const workerInfo = await federatedLearning.workerInfo(worker.address);
      if (workerInfo.hasLearningRight) {
        if (workerInfo.latestModelIndex > latestModelIndex) {
          latestModelIndex = workerInfo.latestModelIndex;
          workerWithLatestLearningRight = worker;
        }
      }
    }
    return workerWithLatestLearningRight;
  }
});

