const hre = require("hardhat");

async function main() {
  const AggregatorV3 = await hre.ethers.getContractFactory("AggregatorV3");
  const AggregatorV3Contract = await AggregatorV3.deploy(
    "0x8A753747A1Fa494EC906cE90E9f37563A8AF630e"
  );

  await AggregatorV3Contract.deployed();
  console.log("AggregatorV3Contract @ ", AggregatorV3Contract.address);

  const pricePrediction = await hre.ethers.getContractFactory(
    "pricePrediction"
  );
  const pricePredictionContract = await pricePrediction.deploy(
    AggregatorV3Contract.address,
    1000000000000000,
    1000
  );

  await pricePredictionContract.deployed();
  console.log("pricePredictionContract @ ", pricePredictionContract.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
