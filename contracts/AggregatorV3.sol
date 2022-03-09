//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract AggregatorV3 {
    AggregatorV3Interface internal priceFeed;

    constructor(address _PairAddress) {
        priceFeed = AggregatorV3Interface(_PairAddress);
    }

    function getLatestPrice()
        public
        view
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        )
    {
        (
            uint80 roundID,
            int256 price,
            uint256 startedAt,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        return (roundID, price, startedAt, timeStamp, answeredInRound);
    }
}
