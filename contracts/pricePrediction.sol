//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);

    function getLatestPrice()
        external
        view
        returns (
            uint80 roundID,
            int256 price,
            uint256 startedAt,
            uint256 timeStamp,
            uint80 answeredInRound
        );
}

contract pricePrediction is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    AggregatorV3Interface public oracle;

    bool public genesisLockOnce = false;
    bool public genesisStartOnce = false;

    address public adminAddress;
    address public operatorAddress;

    uint256 public minBetAmount;
    uint256 public treasuryFee;
    uint256 public treasuryAmount;

    uint256 public currentEpoch;
    uint256 public oracleLatestRoundId;

    uint256 public constant MAX_TREASURY_FEE = 1000;

    mapping(uint256 => mapping(address => BetInfo)) public ledger;
    mapping(uint256 => Round) public rounds;
    mapping(address => uint256[]) public userRounds;

    enum Position {
        Bull,
        Bear
    }

    struct Round {
        uint256 epoch;
        uint256 startTimestamp;
        uint256 lockTimestamp;
        uint256 closeTimestamp;
        int256 lockPrice;
        int256 closePrice;
        uint256 lockOracleId;
        uint256 closeOracleId;
        uint256 totalAmount;
        uint256 bullAmount;
        uint256 bearAmount;
        uint256 rewardBaseCalAmount;
        uint256 rewardAmount;
        bool oracleCalled;
    }

    struct BetInfo {
        Position position;
        uint256 amount;
        bool claimed; // default false
    }

    event BetBear(
        address indexed sender,
        uint256 indexed epoch,
        uint256 amount
    );
    event BetBull(
        address indexed sender,
        uint256 indexed epoch,
        uint256 amount
    );
    event Claim(address indexed sender, uint256 indexed epoch, uint256 amount);
    event EndRound(
        uint256 indexed epoch,
        uint256 indexed roundId,
        int256 price
    );
    event LockRound(
        uint256 indexed epoch,
        uint256 indexed roundId,
        int256 price
    );

    event NewAdminAddress(address admin);
    event NewBufferAndIntervalSeconds(
        uint256 bufferSeconds,
        uint256 intervalSeconds
    );
    event NewMinBetAmount(uint256 indexed epoch, uint256 minBetAmount);
    event NewTreasuryFee(uint256 indexed epoch, uint256 treasuryFee);
    event NewOperatorAddress(address operator);
    event NewOracle(address oracle);
    event NewOracleUpdateAllowance(uint256 oracleUpdateAllowance);

    event Pause(uint256 indexed epoch);
    event RewardsCalculated(
        uint256 indexed epoch,
        uint256 rewardBaseCalAmount,
        uint256 rewardAmount,
        uint256 treasuryAmount
    );

    event StartRound(uint256 indexed epoch);
    event TokenRecovery(address indexed token, uint256 amount);
    event TreasuryClaim(uint256 amount);
    event Unpause(uint256 indexed epoch);

    modifier onlyAdmin() {
        require(msg.sender == adminAddress, "Not admin");
        _;
    }

    modifier onlyAdminOrOperator() {
        require(
            msg.sender == adminAddress || msg.sender == operatorAddress,
            "Not operator/admin"
        );
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operatorAddress, "Not operator");
        _;
    }

    modifier notContract() {
        require(!_isContract(msg.sender), "Contract not allowed");
        require(msg.sender == tx.origin, "Proxy contract not allowed");
        _;
    }

    constructor(
        address _oracleAddress,
        uint256 _minBetAmount,
        uint256 _treasuryFee
    ) {
        require(_treasuryFee <= MAX_TREASURY_FEE, "Treasury fee too high");

        oracle = AggregatorV3Interface(_oracleAddress);
        adminAddress = msg.sender;
        operatorAddress = msg.sender;
        minBetAmount = _minBetAmount;
        treasuryFee = _treasuryFee;
    }

    function gensisStartPrediction() external whenNotPaused onlyOperator {
        require(!genesisStartOnce, "You can only once gensisStartPrediction");

        currentEpoch = currentEpoch + 1;
        _startNewRound(currentEpoch);
        genesisStartOnce = true;
    }

    function _startNewRound(uint256 _epoch) internal {
        Round storage round = rounds[_epoch];
        round.startTimestamp = block.timestamp;
        round.lockTimestamp = block.timestamp;
        round.closeTimestamp = block.timestamp;
        round.epoch = _epoch;
        round.totalAmount = 0;

        emit StartRound(_epoch);
    }

    function _safeStartRound(uint256 _epoch) internal {
        require(
            genesisStartOnce,
            "Can only run after genesisStartRound is triggered"
        );
        _startNewRound(_epoch);
    }

    function betBearPrediction(uint256 _epoch)
        external
        payable
        whenNotPaused
        nonReentrant
        notContract
    {
        require(_epoch == currentEpoch - 1, "your epoch is invalid");
        require(epochIsBettable(_epoch), "your epoch is not bettable");
        require(msg.value >= minBetAmount, "bet amount must be greater");
        require(
            ledger[_epoch][msg.sender].amount == 0,
            "you can only bet once"
        );

        uint256 amount = msg.value;
        Round storage round = rounds[_epoch];
        round.totalAmount = round.totalAmount + amount;
        round.bearAmount = round.bearAmount + amount;

        BetInfo storage betInfo = ledger[_epoch][msg.sender];
        betInfo.amount = amount;
        betInfo.position = Position.Bear;
        userRounds[msg.sender].push(_epoch);

        emit BetBear(msg.sender, _epoch, amount);
    }

    function betBullPrediction(uint256 _epoch)
        external
        payable
        whenNotPaused
        nonReentrant
        notContract
    {
        require(_epoch == currentEpoch - 1, "your epoch is invalid");
        require(epochIsBettable(_epoch), "your epoch is not bettable");
        require(msg.value >= minBetAmount, "bet amount must be greater");
        require(
            ledger[_epoch][msg.sender].amount == 0,
            "you can only bet once"
        );

        uint256 amount = msg.value;
        Round storage round = rounds[_epoch];
        round.totalAmount = round.totalAmount + amount;
        round.bullAmount = round.bullAmount + amount;

        BetInfo storage betInfo = ledger[_epoch][msg.sender];
        betInfo.amount = amount;
        betInfo.position = Position.Bull;
        userRounds[msg.sender].push(_epoch);

        emit BetBear(msg.sender, _epoch, amount);
    }

    function epochIsBettable(uint256 _epoch) internal view returns (bool) {
        return
            rounds[_epoch].startTimestamp != 0 &&
            rounds[_epoch].lockTimestamp != 0;
    }

    function gensisLockRound() external whenNotPaused onlyOperator {
        require(genesisStartOnce, "Can only run after gensisStartPrediction");
        require(!genesisLockOnce, "Can only run genesisLockRound once");

        (uint80 currentRoundId, int256 currentPrice) = _getPriceFromOracle();

        oracleLatestRoundId = uint256(currentRoundId);

        _safeLockRound(currentEpoch, currentRoundId, currentPrice);

        currentEpoch = currentEpoch + 1;
        _startNewRound(currentEpoch);
        genesisLockOnce = true;
    }

    function executeRound() external whenNotPaused onlyOperator {
        require(
            genesisStartOnce && genesisLockOnce,
            "Can only run after genesisStartRound and genesisLockRound is triggered"
        );

        (uint80 currentRoundId, int256 currentPrice) = _getPriceFromOracle();

        oracleLatestRoundId = uint256(currentRoundId);

        _safeLockRound(currentEpoch, currentRoundId, currentPrice);
        _safeEndRound(currentEpoch - 1, currentRoundId, currentPrice);
        _calculateRewards(currentEpoch - 1);

        currentEpoch = currentEpoch + 1;
        _safeStartRound(currentEpoch);
    }

    function _safeLockRound(
        uint256 _epoch,
        uint256 _roundId,
        int256 _currentPrice
    ) internal {
        require(
            rounds[_epoch].startTimestamp != 0,
            "Can only lock round after round has started"
        );
        Round storage round = rounds[_epoch];
        round.closeTimestamp = block.timestamp;
        round.lockPrice = 3;
        round.lockOracleId = _roundId;

        emit LockRound(_epoch, _roundId, round.lockPrice);
    }

    function _safeEndRound(
        uint256 _epoch,
        uint256 _roundId,
        int256 _currentPrice
    ) internal {
        require(
            rounds[_epoch].startTimestamp != 0,
            "Can only lock round after round has started"
        );

        Round storage round = rounds[_epoch];
        round.closePrice = 2;
        round.closeOracleId = _roundId;
        round.oracleCalled = true;

        emit EndRound(_epoch, _roundId, round.closePrice);
    }

    function _calculateRewards(uint256 _epoch) internal {
        require(
            rounds[_epoch].rewardBaseCalAmount == 0 &&
                rounds[_epoch].rewardAmount == 0,
            "Rewards calculated"
        );
        Round storage round = rounds[_epoch];
        uint256 rewardBaseCalAmount;
        uint256 treasuryAmt;
        uint256 rewardAmount;

        if (round.closePrice > round.lockPrice) {
            rewardBaseCalAmount = round.bullAmount;
            treasuryAmt = (round.totalAmount * treasuryFee) / 10000;
            rewardAmount = round.totalAmount - treasuryAmt;
        } else if (round.closePrice < round.lockPrice) {
            rewardBaseCalAmount = round.bearAmount;
            treasuryAmt = (round.totalAmount * treasuryFee) / 10000;
            rewardAmount = round.totalAmount - treasuryAmt;
        } else {
            rewardBaseCalAmount = 0;
            rewardAmount = 0;
            treasuryAmt = round.totalAmount;
        }
        round.rewardBaseCalAmount = rewardBaseCalAmount;
        round.rewardAmount = rewardAmount;

        treasuryAmount += treasuryAmt;

        emit RewardsCalculated(
            _epoch,
            rewardBaseCalAmount,
            rewardAmount,
            treasuryAmt
        );
    }

    function getSomeAnswer(uint256 _epoch) external view returns (uint256) {
        Round memory round = rounds[_epoch];
        return round.rewardAmount;
    }

    function claimReward(uint256[] calldata _epochs)
        external
        nonReentrant
        notContract
    {
        uint256 reward;

        for (uint256 i = 0; i < _epochs.length; i++) {
            require(
                rounds[_epochs[i]].startTimestamp != 0,
                "Round has not started"
            );

            uint256 addedReward = 0;

            if (rounds[_epochs[i]].oracleCalled) {
                require(
                    isClaimable(_epochs[i], msg.sender),
                    "Not eligible for claim"
                );
                Round memory round = rounds[_epochs[i]];
                addedReward =
                    (ledger[_epochs[i]][msg.sender].amount *
                        round.rewardAmount) /
                    round.rewardBaseCalAmount;
            } else {
                require(
                    isRefundable(_epochs[i], msg.sender),
                    "Not eligible for refund"
                );
                addedReward = ledger[_epochs[i]][msg.sender].amount;
            }

            ledger[_epochs[i]][msg.sender].claimed = true;
            reward += addedReward;

            emit Claim(msg.sender, _epochs[i], addedReward);
        }

        if (reward > 0) {
            _safeTransferBNB(address(msg.sender), reward);
        }
    }

    function _safeTransferBNB(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}("");
        require(success, "TransferHelper: BNB_TRANSFER_FAILED");
    }

    function getOracleCalled(uint256 _epoch) external view returns (bool) {
        Round memory round = rounds[_epoch];
        return round.oracleCalled;
    }

    function isClaimable(uint256 _epoch, address _user)
        public
        view
        returns (bool)
    {
        BetInfo memory betInfo = ledger[_epoch][_user];
        Round memory round = rounds[_epoch];
        if (round.lockPrice == round.closePrice) {
            return false;
        }
        return
            round.oracleCalled &&
            betInfo.amount != 0 &&
            !betInfo.claimed &&
            ((round.closePrice > round.lockPrice &&
                betInfo.position == Position.Bull) ||
                (round.closePrice < round.lockPrice &&
                    betInfo.position == Position.Bear));
    }

    function isRefundable(uint256 _epoch, address _user)
        public
        view
        returns (bool)
    {
        BetInfo memory betInfo = ledger[_epoch][_user];
        Round memory round = rounds[_epoch];
        return !round.oracleCalled && !betInfo.claimed && betInfo.amount != 0;
    }

    function _getPriceFromOracle() internal view returns (uint80, int256) {
        (uint80 roundId, int256 price, , , ) = oracle.getLatestPrice();
        return (roundId, price);
    }

    function getUserRoundsLength(address user) external view returns (uint256) {
        return userRounds[user].length;
    }

    function _isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
}
