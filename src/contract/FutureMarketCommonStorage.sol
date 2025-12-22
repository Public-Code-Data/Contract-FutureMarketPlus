// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

abstract contract FutureMarketCommonStorage {
    uint32 public startTime;
    uint32 public endTime;
    uint32 public resolutionTime;

    uint256 public constant BET_AMOUNTS = 10 * 10 ** 6;
    address public constant USDT_ADDRESS =
        0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;
    address public constant COMMITTEE_ADDRESS =
        0xC565FC29F6df239Fe3848dB82656F2502286E97d;

    

    address public factoryAddress;
    string public marketName;
    string public marketSymbol;

    uint256 public correctPoints;
    uint256 public errorPoints;
    bool public answerStatus;
    Answer public correctAnswer;

    mapping(address => bool) public userBetStatus;
    mapping(address => Answer) public userAnswer;
    address public prizePoolAddress;

    event SetPrizePoolAddressuy(address indexed newPrizePool);

    event Buy(
        address indexed recipient,
        address indexed collection,
        uint256 amounts,
        Answer answer
    );

    event ResolutionAnswer(
        address indexed recipient,
        address indexed collection,
        Answer answer,
        uint256 correctPoints,
        uint256 errorPoints
    );

    enum Answer {
        Empty,
        A,
        B
    }
}
