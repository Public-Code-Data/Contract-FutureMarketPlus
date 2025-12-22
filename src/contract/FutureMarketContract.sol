// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./FutureMarketCommonStorage.sol";

contract FutureMarketContract is FutureMarketCommonStorage, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public usdtToken;
    bool private _initialized;

    constructor() ReentrancyGuard() {}

    function initialize(
        string calldata name_,
        string calldata symbol_,
        bytes calldata packedData
    ) external {
        require(!_initialized, "Already initialized");
        _initialized = true;
        marketName = name_;
        marketSymbol = symbol_;

        initPublicTime(packedData);
        factoryAddress = msg.sender;

        usdtToken = IERC20(USDT_ADDRESS);

        prizePoolAddress = 0xC565FC29F6df239Fe3848dB82656F2502286E97d;
    }

    function initPublicTime(bytes calldata packedData) internal {
        require(
            packedData.length == 96,
            "packedData must be 96 bytes (3 uint32)"
        );

        (uint32 _startTime, uint32 _endTime, uint32 _resolutionTime) = abi
            .decode(packedData, (uint32, uint32, uint32));
        require(
            _endTime > _startTime && _resolutionTime > _endTime,
            "Invalid time"
        );

        startTime = _startTime;
        endTime = _endTime;
        resolutionTime = _resolutionTime;
    }

    modifier checkPublicPhase() {
        require(block.timestamp >= startTime, "Time is not up");
        require(block.timestamp <= endTime, "Time is up");
        _;
    }

    function setPayToken(address _erc20TokenAddress) external {
        require(msg.sender == COMMITTEE_ADDRESS, "Invalid sender");
        require(_erc20TokenAddress != address(0), "Invalid address");
        usdtToken = IERC20(_erc20TokenAddress);
    }

    function setPrizePoolAddress(address _prizePoolAddress) external {
        require(msg.sender == COMMITTEE_ADDRESS, "Invalid sender");
        require(_prizePoolAddress != address(0), "Invalid address");
        prizePoolAddress = _prizePoolAddress;

        emit SetPrizePoolAddressuy(prizePoolAddress);
    }

    function setPublicTime(bytes calldata packedData) external {
        initPublicTime(packedData);
    }

    function buy(
        uint256 _amount,
        Answer _answer
    ) external nonReentrant checkPublicPhase {
        require(_answer != Answer.Empty, "Invalid _answer");
        require(prizePoolAddress != address(0), "Invalid pool address");

        address sender = msg.sender;
        require(!userBetStatus[sender], "Already buy");
        require(_amount == BET_AMOUNTS, "Invalid amount");

        require(
            usdtToken.balanceOf(sender) >= BET_AMOUNTS,
            "Invalid amount:Insufficient balance"
        );
        usdtToken.safeTransferFrom(sender, prizePoolAddress, _amount);

        userBetStatus[sender] = true;
        userAnswer[sender] = _answer;

        emit Buy(sender, address(this), _amount, _answer);
    }

    function resolutionAnswer(
        Answer _answer,
        uint256 _correctPoints,
        uint256 _errorPoints
    ) external {
        require(_answer != Answer.Empty, "Invalid _answer");
        require(block.timestamp >= resolutionTime, "Event not completed");

        require(!answerStatus, "Already announced");

        require(msg.sender == COMMITTEE_ADDRESS, "Invalid sender");

        correctAnswer = _answer;
        answerStatus = true;
        correctPoints = _correctPoints;
        errorPoints = _errorPoints;

        emit ResolutionAnswer(
            msg.sender,
            address(this),
            _answer,
            _correctPoints,
            _errorPoints
        );
    }

    function getPointsReward() external view returns (uint256) {
        require(answerStatus, "No correct solution");
        address sender = msg.sender;
        if (!userBetStatus[sender]) {
            return 0;
        }
        return
            userAnswer[sender] == correctAnswer ? correctPoints : errorPoints;
    }

    receive() external payable {}

    function emergencyWithdraw(address token, uint256 amount) external {
        require(
            msg.sender == COMMITTEE_ADDRESS,
            "Invalid sender: Only committee address"
        );

        address payable to = payable(COMMITTEE_ADDRESS);
        if (token == address(0)) {
            (bool success, ) = to.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }
}
