// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import "./contract/FutureMarketContract.sol";

contract FutureMarketFactoryContract is
    ERC721Upgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    // 类型 -> Beacon
    mapping(uint256 => UpgradeableBeacon) public beacons;

    // 市场地址 -> tokenId
    mapping(address => uint256) public marketToTokenId;

    address public pointsSigner;
    address public initialCommittee;

    event BeaconUpgraded(uint256 indexed marketType, address indexed newImplementation);
    event MarketCreated(
        address indexed market,
        address indexed owner,
        uint256 indexed tokenId,
        uint256 marketType,
        string name,
        string symbol
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _initialImplementation,
        address _pointsSigner,
        address _initialCommittee
    ) external initializer {
        __ERC721_init("FutureMarket Owner", "FMOWNER");
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        require(_initialImplementation != address(0), "Invalid impl");
        require(_pointsSigner != address(0), "Invalid signer");

        pointsSigner = _pointsSigner;
        initialCommittee = _initialCommittee;

        // 创建默认类型 0 的 Beacon
        beacons[0] = new UpgradeableBeacon(_initialImplementation, address(this));
    }

    /**
     * @dev 创建新预测市场（使用官方 BeaconProxy，最稳定）
     */
    function createFutureMarket(
        uint256 marketType,
        bytes32 collectionId, // 用于防抢注检查
        string calldata name,
        string calldata symbol,
        bytes calldata packedTimeData
    ) external returns (address market) {
        // 防抢注：salt 前 20 字节必须是调用者
        if (address(bytes20(collectionId)) != msg.sender) revert("Invalid caller");

        UpgradeableBeacon beacon = beacons[marketType];
        require(address(beacon) != address(0), "Invalid marketType");

        // 构造初始化数据
        bytes memory initData = abi.encodeCall(
            FutureMarketContract.initialize,
            (name, symbol, initialCommittee, pointsSigner, packedTimeData)
        );

        // 使用官方 BeaconProxy 部署（安全、可靠、支持初始化）
        market = address(new BeaconProxy(address(beacon), initData));

        uint256 tokenId = uint256(uint160(market));
        _safeMint(msg.sender, tokenId);
        marketToTokenId[market] = tokenId;

        emit MarketCreated(market, msg.sender, tokenId, marketType, name, symbol);
    }

  

    /**
     * @dev 一键升级所有同类型市场
     */
    function upgradeMarketType(uint256 marketType, address newImplementation) external onlyOwner {
        require(newImplementation != address(0), "Invalid impl");
        UpgradeableBeacon beacon = beacons[marketType];
        require(address(beacon) != address(0), "Invalid type");

        beacon.upgradeTo(newImplementation);
        emit BeaconUpgraded(marketType, newImplementation);
    }

    /**
     * @dev 添加新市场类型
     */
    function addMarketType(uint256 marketType, address implementation) external onlyOwner {
        require(address(beacons[marketType]) == address(0), "Type exists");
        beacons[marketType] = new UpgradeableBeacon(implementation, address(this));
    }

    // ============ 配置 ============
    function setPointsSigner(address newSigner) external onlyOwner {
        require(newSigner != address(0), "Zero address");
        pointsSigner = newSigner;
    }

    function setInitialCommittee(address newCommittee) external onlyOwner {
        require(newCommittee != address(0), "Zero address");
        initialCommittee = newCommittee;
    }

    // ============ ERC721 ============
    function burnOwnership(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        _burn(tokenId);
        delete marketToTokenId[address(uint160(tokenId))];
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    // ============ 查看 ============
    function getBeacon(uint256 marketType) external view returns (address) {
        return address(beacons[marketType]);
    }

    function getImplementation(uint256 marketType) external view returns (address) {
        return beacons[marketType].implementation();
    }
}