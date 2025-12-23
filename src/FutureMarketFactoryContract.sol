// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

import "./contract/FutureMarketContract.sol";

contract FutureMarketFactoryContract is
    ERC721Upgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    address constant MINIMAL_PROXY_TEMPLATE =
        0x3f0091d31f1E3E0FC8b0e1C43e2e7eF4e8EF33e2;

    // 类型 -> Beacon
    mapping(uint256 => UpgradeableBeacon) public beacons;

    // 市场地址 -> tokenId
    mapping(address => uint256) public marketToTokenId;

    address public pointsSigner;
    address public initialCommittee;

    event BeaconUpgraded(
        uint256 indexed marketType,
        address indexed newImplementation
    );
    event MarketCreated(
        address indexed market,
        address indexed owner,
        uint256 tokenId
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
        beacons[0] = new UpgradeableBeacon(
            _initialImplementation,
            address(this)
        );
    }

    function createFutureMarket(
        uint256 marketType,
        bytes32 collectionId,
        string calldata name,
        string calldata symbol,
        bytes calldata packedTimeData
    ) external returns (address market) {
        if (address(bytes20(collectionId)) != msg.sender)
            revert("Invalid caller");

        UpgradeableBeacon beacon = beacons[marketType];
        require(address(beacon) != address(0), "Invalid marketType");

        // 正确：使用固定极简代理字节码地址作为 mother（OpenZeppelin 推荐）

        market = Clones.cloneDeterministic(
            MINIMAL_PROXY_TEMPLATE,
            collectionId
        );

        // 合并初始化，减少局部变量
        bytes memory payload = abi.encodeCall(
            FutureMarketContract.initialize,
            (name, symbol, initialCommittee, pointsSigner, packedTimeData)
        );

        (bool success, ) = market.call(payload);
        require(success, "Initialization failed");

        // 设置 Beacon 地址到 slot 0
        // payload = abi.encodeWithSignature(
        //     "setBeacon(address)",
        //     address(beacon)
        // );
        assembly {
            sstore(0, beacon) // 直接写入 storage slot 0
        }
        (success, ) = market.call(payload);
        require(success, "Set beacon failed");

        // Mint NFT + emit
        uint256 tokenId = uint256(uint160(market));
        _safeMint(msg.sender, tokenId);
        marketToTokenId[market] = tokenId;

        // emit 保持不变（现在栈深度已安全）
        emit MarketCreated(market, msg.sender, tokenId);
    }
    /**
     * @dev 预测地址（使用固定极简代理字节码）
     */
    function predictMarketAddress(
        uint256 marketType,
        bytes32 collectionId
    ) external view returns (address) {
        require(address(beacons[marketType]) != address(0), "Invalid type");
        return
            Clones.predictDeterministicAddress(
                MINIMAL_PROXY_TEMPLATE, // 同上固定地址
                collectionId,
                address(this)
            );
    }

    /**
     * @dev 升级指定类型的所有市场
     */
    function upgradeMarketType(
        uint256 marketType,
        address newImplementation
    ) external onlyOwner {
        UpgradeableBeacon beacon = beacons[marketType];
        require(address(beacon) != address(0), "Invalid type");
        beacon.upgradeTo(newImplementation);
        emit BeaconUpgraded(marketType, newImplementation);
    }

    /**
     * @dev 添加新市场类型
     */
    function addMarketType(
        uint256 marketType,
        address implementation
    ) external onlyOwner {
        require(address(beacons[marketType]) == address(0), "Type exists");
        beacons[marketType] = new UpgradeableBeacon(
            implementation,
            address(this)
        );
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

    function getImplementation(
        uint256 marketType
    ) external view returns (address) {
        return beacons[marketType].implementation();
    }
}
