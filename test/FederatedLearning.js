// test/FederatedLearning.test.js
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("FederatedLearning", function () {
  let FederatedLearning, federatedLearning, initialModelCID, alice, bob, charlie, david, eve, frank, george, hannah, ian, jane, kyle, lisa;

  beforeEach(async () => {
    FederatedLearning = await ethers.getContractFactory("FederatedLearning");
    initialModelCID = "initialModelCID";
    [alice, bob, charlie, david, eve, frank, george, hannah, ian, jane, kyle, lisa] = await ethers.getSigners();
    federatedLearning = await FederatedLearning.deploy(initialModelCID);
  });

  describe("register", () => {
    it("should allow clients to register", async () => {
      await federatedLearning.connect(alice).register();
      expect((await federatedLearning.clientInfo(alice.address)).registered).to.equal(true);
    });

    it("should not allow clients to register twice", async () => {
      await federatedLearning.connect(alice).register();
      await expect(federatedLearning.connect(alice).register()).to.be.revertedWith("Already registered");
    });

    it("should grant learning rights when client number reaches threshold", async () => {
      const clientPromises = [alice, bob, charlie, david, eve, frank, george, hannah, ian, jane].map((client) =>
        federatedLearning.connect(client).register()
      );
      await Promise.all(clientPromises);

      let numClientsWithRight = 0;
      for (const client of [alice, bob, charlie, david, eve, frank, george, hannah, ian, jane]) {
        const clientInfo = await federatedLearning.clientInfo(client.address);
        if (clientInfo.hasLearningRight) {
          numClientsWithRight++;
        }
      }
      expect(numClientsWithRight).to.equal(3);
    });
  });

  describe("submitModel", () => {
    beforeEach(async () => {
      const clientPromises = [alice, bob, charlie, david, eve, frank, george, hannah, ian, jane].map((client) =>
        federatedLearning.connect(client).register()
      );
      await Promise.all(clientPromises);
    });

    it("should not allow submitting model without enough clients", async () => {
      const federatedLearning2 = await FederatedLearning.deploy(initialModelCID);
      await federatedLearning2.connect(alice).register();
      await expect(federatedLearning2.connect(alice).submitModel("newModelCID", [])).to.be.revertedWith("Not enough clients");
    });

    it("should not allow submitting model without learning right", async () => {
      await expect(federatedLearning.connect(kyle).submitModel("newModelCID", [])).to.be.revertedWith("No learning right");
    });

    it("should not allow submitting an existing model", async () => {
      const clientWithLearningRight = await getClientWithLearningRight();
      await federatedLearning.connect(clientWithLearningRight).submitModel("newModelCID", []);
      const clientWithLearningRight2 = await getClientWithLearningRight();
      await expect(federatedLearning.connect(clientWithLearningRight2).submitModel("newModelCID", [])).to.be.revertedWith("Model already exists");
    });

    it("should allow submitting a new model and update learning rights", async () => {
      const clientWithLearningRight = await getClientWithLearningRight();
      await federatedLearning.connect(clientWithLearningRight).submitModel("newModelCID", []);
      
      // Check that the new model is added to the models array
      const model = await federatedLearning.models(0);
      expect({
        CID: model.CID,
        author: model.author
      }).to.deep.equal({
        CID: "newModelCID",
        author: clientWithLearningRight.address
      });

      // Check that the client submitted the model has no learning right
      const clientInfo = await federatedLearning.clientInfo(clientWithLearningRight.address);
      expect(clientInfo.hasLearningRight).to.equal(false);
      
      // Check that the client with latest learning right has correct latestModelIndex
      const clientWithLatestLearningRight = await getClientWithLatestLearningRight();
      const clientInfoWithLatestLearningRight = await federatedLearning.clientInfo(clientWithLatestLearningRight.address);

      expect({
        registered: clientInfoWithLatestLearningRight.registered,
        hasLearningRight: clientInfoWithLatestLearningRight.hasLearningRight,
        latestModelIndex: Number(clientInfoWithLatestLearningRight.latestModelIndex),
      }).to.deep.equal({
        registered: true,
        hasLearningRight: true,
        latestModelIndex: 1,
      });
  
      let numClientsWithRight = 0;
      for (const client of [alice, bob, charlie, david, eve, frank, george, hannah, ian, jane]) {
        const clientInfo = await federatedLearning.clientInfo(client.address);
        if (clientInfo.hasLearningRight) {
          numClientsWithRight++;
        }
      }
      expect(numClientsWithRight).to.equal(3);
    });
  

    it("should mint tokens for voted models", async () => {
      const client = await getClientWithLearningRight();
      await federatedLearning.connect(client).submitModel("newModelCID", []);
      const client2 = await getClientWithLatestLearningRight();
      await federatedLearning.connect(client2).submitModel("newModelCID2", ["newModelCID"]);

      expect(await federatedLearning.balanceOf(client.address)).to.equal(1);
      expect(await federatedLearning.balanceOf(client2.address)).to.equal(0);
    });
  });

  async function getClientWithLearningRight() {
    for (const client of [alice, bob, charlie, david, eve, frank, george, hannah, ian, jane]) {
      const clientInfo = await federatedLearning.clientInfo(client.address);
      if (clientInfo.hasLearningRight) {
        return client;
      }
    }
  }

  async function getClientWithLatestLearningRight() {
    let clientWithLatestLearningRight;
    let latestModelIndex = 0;
    for (const client of [alice, bob, charlie, david, eve, frank, george, hannah, ian, jane]) {
      const clientInfo = await federatedLearning.clientInfo(client.address);
      if (clientInfo.hasLearningRight) {
        if (clientInfo.latestModelIndex > latestModelIndex) {
          latestModelIndex = clientInfo.latestModelIndex;
          clientWithLatestLearningRight = client;
        }
      }
    }
    return clientWithLatestLearningRight;
  }
});

