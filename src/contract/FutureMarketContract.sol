// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./FutureMarketCommonStorage.sol";

contract FutureMarketContract is
    Initializable,
    OwnableUpgradeable,
    EIP712Upgradeable
{
    using FutureMarketCommonStorage for FutureMarketCommonStorage.Layout;
    using SafeERC20 for IERC20;

    bytes32 public constant BET_TYPEHASH =
        keccak256(
            "Bet(address user,uint8 answer,uint256 amount,uint256 nonce,uint256 deadline)"
        );

    uint256 public constant BET_UNIT = 100; // 100 积分单位

    event Bet(
        address indexed user,
        uint8 indexed answer,
        uint256 amount,
        uint256 nonces
    );
    event Resolved(
        FutureMarketCommonStorage.Answer winningAnswer,
        uint256 rewardPerPoint
    );
    event Claimed(address indexed user, uint256 reward);
    event CommitteeChanged(address indexed oldAddr, address indexed newAddr);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        address initialCommittee_,
        address pointsSigner_,
        bytes calldata packedTime // 96 bytes: start, end, resolution (uint32 x3)
    ) external initializer {
        __Ownable_init(msg.sender);
        __EIP712_init(name_, symbol_);

        FutureMarketCommonStorage.Layout storage s = FutureMarketCommonStorage
            .layout();
        s.marketName = name_;
        s.marketSymbol = symbol_;
        s.pointsSigner = pointsSigner_;
        s.committee = initialCommittee_;
        s.factory = msg.sender;

        _initTimes(packedTime);
    }

    function _initTimes(bytes calldata packedTime) internal {
        require(packedTime.length == 96, "packedTime must be 96 bytes");

        (uint32 start, uint32 end, uint32 resolution) = abi.decode(
            packedTime,
            (uint32, uint32, uint32)
        );
        require(end > start && resolution > end, "Invalid times");

        FutureMarketCommonStorage.Layout storage s = FutureMarketCommonStorage
            .layout();
        s.startTime = start;
        s.endTime = end;
        s.resolutionTime = resolution;
    }

    function updateTime(bytes calldata packedTime) external {
        FutureMarketCommonStorage.Layout storage st = FutureMarketCommonStorage
            .layout();
        require(msg.sender == st.committee, "Only committee");
        _initTimes(packedTime);
    }

    function bet(
        uint8 answerRaw, // 1=A, 2=B
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        FutureMarketCommonStorage.Layout storage st = FutureMarketCommonStorage
            .layout();

        require(block.timestamp >= st.startTime, "Not started");
        require(block.timestamp <= st.endTime, "Ended");
        require(block.timestamp <= deadline, "Expired");
        require(answerRaw == 1 || answerRaw == 2, "Invalid answer");
        require(amount > 0 && amount % BET_UNIT == 0, "Invalid amount");

        address user = msg.sender;
        FutureMarketCommonStorage.Answer answer = answerRaw == 1
            ? FutureMarketCommonStorage.Answer.A
            : FutureMarketCommonStorage.Answer.B;

        // ========== 单边限制检查 ==========
        if (st.userSide[user] != FutureMarketCommonStorage.Answer.Empty) {
            // 已经下注过，必须与本次方向一致
            require(st.userSide[user] == answer, "Cannot bet on both sides");
        } else {
            // 首次下注，记录方向
            st.userSide[user] = answer;
        }
        // ==================================

        uint256 currentNonce = st.nonces[user];

        bytes32 structHash = keccak256(
            abi.encode(
                BET_TYPEHASH,
                user,
                answerRaw,
                amount,
                currentNonce,
                deadline
            )
        );
        bytes32 hash = _hashTypedDataV4(structHash);
        require(ECDSA.recover(hash, v, r, s) == st.pointsSigner, "Invalid sig");

        // 统一记录到 betAmounts，并更新总池子
        st.betAmounts[user] += amount;

        if (answer == FutureMarketCommonStorage.Answer.A) {
            st.totalA += amount;
        } else {
            st.totalB += amount;
        }

        st.nonces[user]++;

        emit Bet(user, answerRaw, amount, currentNonce);
    }

    // ============ 开奖（committee） ============
    function resolve(uint8 winningAnswerRaw, uint256 rewardPerPoint) external {
        FutureMarketCommonStorage.Layout storage st = FutureMarketCommonStorage
            .layout();
        require(msg.sender == st.committee, "Only committee");
        require(block.timestamp >= st.resolutionTime, "Too early");
        require(!st.resolved, "Already resolved");
        require(
            winningAnswerRaw == 1 || winningAnswerRaw == 2,
            "Invalid answer"
        );

        st.resolved = true;
        st.winningAnswer = winningAnswerRaw == 1
            ? FutureMarketCommonStorage.Answer.A
            : FutureMarketCommonStorage.Answer.B;
        st.rewardPerPoint = rewardPerPoint;

        emit Resolved(st.winningAnswer, rewardPerPoint);
    }

    // ============ 修改 committee ============
    function setCommittee(address newCommittee) external {
        require(newCommittee != address(0), "Zero address");

        FutureMarketCommonStorage.Layout storage st = FutureMarketCommonStorage
            .layout();
        require(msg.sender == st.pointsSigner, "Invalid address");
        emit CommitteeChanged(st.committee, newCommittee);
        st.committee = newCommittee;
    }

    // ============ 领奖 ============
    function claim() external {
        FutureMarketCommonStorage.Layout storage st = FutureMarketCommonStorage
            .layout();
        require(st.resolved, "Not resolved");

        require(st.userSide[msg.sender] == st.winningAnswer, "Not winner");

        uint256 userBet = st.betAmounts[msg.sender];
        require(userBet > 0, "No bet");

        uint256 reward = userBet * st.rewardPerPoint;
        require(reward > 0, "No reward");
        require(st.claimedReward[msg.sender] == 0, "Already claimed");

        st.claimedReward[msg.sender] = reward;

        emit Claimed(msg.sender, reward);
    }

    // ============ 救援函数 ============
    receive() external payable {}

    function emergencyWithdraw(address token, uint256 amount) external {
        FutureMarketCommonStorage.Layout storage st = FutureMarketCommonStorage
            .layout();
        require(msg.sender == st.committee, "Only committee");
        require(amount > 0, "Amount > 0");

        if (token == address(0)) {
            (bool success, ) = payable(st.committee).call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(st.committee, amount);
        }
    }

    // ============ 查看函数 ============
    function getPendingReward(address user) external view returns (uint256) {
        FutureMarketCommonStorage.Layout storage st = FutureMarketCommonStorage
            .layout();
        if (
            !st.resolved ||
            st.claimedReward[user] > 0 ||
            st.userSide[user] != st.winningAnswer
        ) {
            return 0;
        }
        return st.betAmounts[user] * st.rewardPerPoint;
    }

    function hashTypedDataV4(
        address user,
        uint8 answerRaw,
        uint256 amount,
        uint256 currentNonces,
        uint256 deadline
    ) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                BET_TYPEHASH,
                user,
                answerRaw,
                amount,
                currentNonces,
                deadline
            )
        );
        return _hashTypedDataV4(structHash);
    }

    function getUserBet(
        address user
    )
        external
        view
        returns (uint256 amount, FutureMarketCommonStorage.Answer side)
    {
        FutureMarketCommonStorage.Layout storage st = FutureMarketCommonStorage
            .layout();
        return (st.betAmounts[user], st.userSide[user]);
    }

    function getPointsSigner() external view returns (address) {
        return FutureMarketCommonStorage.layout().pointsSigner;
    }

    function getCommittee() external view returns (address) {
        return FutureMarketCommonStorage.layout().committee;
    }

    function marketName() external view returns (string memory) {
        return FutureMarketCommonStorage.layout().marketName;
    }

    function marketSymbol() external view returns (string memory) {
        return FutureMarketCommonStorage.layout().marketSymbol;
    }

    function startTime() external view returns (uint32) {
        return FutureMarketCommonStorage.layout().startTime;
    }

    function endTime() external view returns (uint32) {
        return FutureMarketCommonStorage.layout().endTime;
    }

    function resolutionTime() external view returns (uint32) {
        return FutureMarketCommonStorage.layout().resolutionTime;
    }

    function resolved() external view returns (bool) {
        return FutureMarketCommonStorage.layout().resolved;
    }

    function winningAnswer()
        external
        view
        returns (FutureMarketCommonStorage.Answer)
    {
        return FutureMarketCommonStorage.layout().winningAnswer;
    }

    function getRewardPerPoint() external view returns (uint256) {
        return FutureMarketCommonStorage.layout().rewardPerPoint;
    }

    function totalBetA() external view returns (uint256) {
        return FutureMarketCommonStorage.layout().totalA;
    }

    function totalBetB() external view returns (uint256) {
        return FutureMarketCommonStorage.layout().totalB;
    }
    function nonces(address user) external view returns (uint256) {
        require(user != address(0), "Invalid user");
        return FutureMarketCommonStorage.layout().nonces[user];
    }

    function getMarketInfo()
        external
        view
        returns (
            string memory name,
            string memory symbol,
            uint32 start,
            uint32 end,
            uint32 resolution,
            bool isResolved,
            FutureMarketCommonStorage.Answer winner,
            uint256 rewardPerPoint,
            uint256 totalA,
            uint256 totalB,
            address committee
        )
    {
        FutureMarketCommonStorage.Layout storage s = FutureMarketCommonStorage
            .layout();
        return (
            s.marketName,
            s.marketSymbol,
            s.startTime,
            s.endTime,
            s.resolutionTime,
            s.resolved,
            s.winningAnswer,
            s.rewardPerPoint,
            s.totalA,
            s.totalB,
            s.committee
        );
    }
}
