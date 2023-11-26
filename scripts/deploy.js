const hre = require("hardhat");

async function main() {
  const FederatedLearning = await hre.ethers.getContractFactory("CABFL");
  const federatedLearning = await FederatedLearning.deploy("SampleInitialModelCID", 10, 5, 5, 1);

  await federatedLearning.deployed();

  console.log("FederatedLearning deployed to:", federatedLearning.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
