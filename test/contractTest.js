const { ethers } = require("hardhat");
const { expect } = require("chai");

const provider = new ethers.providers.JsonRpcProvider(
  "https://eth-rinkeby.alchemyapi.io/v2/BeL-9jQ8nULR3W12GKw5y137CZnwt7Ur"
);

describe("pricePrediction", function () {
  it("we can enter", async function () {
    let currentEpoch;
    let executeRoundTX;

    let isClaimable;
    let isRefundable;

    let getOracleCalled;

    const [owner] = await ethers.getSigners();

    // deploy AggregatorV3
    const AggregatorV3 = await ethers.getContractFactory("AggregatorV3");
    const AggregatorV3Contract = await AggregatorV3.deploy(
      "0x8A753747A1Fa494EC906cE90E9f37563A8AF630e"
    );
    await AggregatorV3Contract.deployed();
    console.log("AggregatorV3Contract @ ", AggregatorV3Contract.address);

    const pricePrediction = await ethers.getContractFactory("pricePrediction");
    const pricePredictionContract = await pricePrediction.deploy(
      AggregatorV3Contract.address,
      ethers.utils.parseEther("0.1"),
      1000
    );

    await pricePredictionContract.deployed();
    console.log("pricePredictionContract @ ", pricePredictionContract.address);

    // get informations
    const genesisStartOnce = await pricePredictionContract.genesisStartOnce();
    expect(genesisStartOnce).to.equal(false);

    const genesisLockOnce = await pricePredictionContract.genesisLockOnce();
    expect(genesisLockOnce).to.equal(false);

    // start gensis round
    if (genesisStartOnce === false) {
      console.log("Start Gensis Round ....");
      const startGensisRoundTX =
        await pricePredictionContract.gensisStartPrediction();
      await startGensisRoundTX.wait();
    }
    // end gensis close round
    if (genesisLockOnce === false) {
      console.log("Lock Gensis Round ....");
      const lockGensisRoundTX = await pricePredictionContract.gensisLockRound();
      await lockGensisRoundTX.wait();
    }

    // execute round
    console.log("Execute Round ....");
    currentEpoch = await pricePredictionContract.currentEpoch();
    console.log(`currentEpoch is ${currentEpoch}`);
    executeRoundTX = await pricePredictionContract.executeRound();
    await executeRoundTX.wait();
    currentEpoch = await pricePredictionContract.currentEpoch();
    console.log(`currentEpoch is ${currentEpoch}`);

    // bet
    console.log(
      (
        await provider.getBalance(pricePredictionContract.address.toString())
      ).toString()
    );

    console.log("Bet Round ....");
    const betTX = await pricePredictionContract.betBearPrediction(
      currentEpoch - 1,
      { value: ethers.utils.parseEther("0.1") }
    );
    await betTX.wait();
    console.log("Bet Done ....");
    console.log(
      (
        await provider.getBalance(pricePredictionContract.address.toString())
      ).toString()
    );
    console.log(
      (await provider.getBalance(owner.address.toString())).toString()
    );

    // execute round
    console.log("Execute Round ....");
    currentEpoch = await pricePredictionContract.currentEpoch();
    console.log(`currentEpoch is ${currentEpoch}`);
    executeRoundTX = await pricePredictionContract.executeRound();
    await executeRoundTX.wait();
    currentEpoch = await pricePredictionContract.currentEpoch();
    console.log(`currentEpoch is ${currentEpoch}`);

    // claim reward
    console.log("Claim Reward ....");
    const finalEpochsForuser = [];

    const getUserRoundsLength =
      await pricePredictionContract.getUserRoundsLength(owner.address);
    console.log("getUserRoundsLength Owner : ", getUserRoundsLength.toString());

    for (let i = 0; i < getUserRoundsLength; i++) {
      const selectEpoch = await pricePredictionContract.userRounds(
        owner.address,
        i
      );

      getOracleCalled = await pricePredictionContract.getOracleCalled(
        selectEpoch
      );
      console.log(`getOracleCalled for ${selectEpoch}`, getOracleCalled);

      isClaimable = await pricePredictionContract.isClaimable(
        selectEpoch,
        owner.address
      );
      console.log(`isClaimable for ${selectEpoch}`, isClaimable);

      isRefundable = await pricePredictionContract.isRefundable(
        selectEpoch,
        owner.address
      );
      console.log(`isRefundable for ${selectEpoch}`, isRefundable);

      if (isClaimable || isRefundable) {
        finalEpochsForuser.push(selectEpoch);
      }
    }

    console.log(finalEpochsForuser.length);

    const claimRewardTX = await pricePredictionContract.claimReward(
      finalEpochsForuser
    );
    await claimRewardTX.wait();
    console.log(
      (
        await provider.getBalance(pricePredictionContract.address.toString())
      ).toString()
    );
    console.log(
      (await provider.getBalance(owner.address.toString())).toString()
    );
  }).timeout(1000000);
});
