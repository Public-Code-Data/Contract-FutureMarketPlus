// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TenXGenesis721NFT is
    Initializable,
    ERC721Upgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    IERC20 public usdt; // USDT 合约地址
    uint256 public price; // 当前 mint 价格（单位：USDT，6 位小数）
    uint256 public constant MAX_PER_WALLET = 10; // 每个钱包最多 mint 10 个
    uint256 public constant MAX_TOTAL_SUPPLY = 10000; // 总供应量上限 10000 个
    string public baseURI; // 统一 metadata URI（所有 NFT 图片相同）

    address public bankAddress; // 收款地址（USDT 直接转给它）

    uint256 public totalSupply; // 当前已铸造数量
    mapping(address => uint256) public mintedCount; // 每个地址已 mint 数量

    event Minted(address indexed to, uint256 indexed tokenId, uint256 price);
    event PriceUpdated(uint256 oldPrice, uint256 newPrice);
    event BaseURIUpdated(string oldURI, string newURI);
    event BankAddressUpdated(address indexed oldBank, address indexed newBank);
    event PayTokenUpdated(address indexed newToken);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __ERC721_init("10x Genesis NFT", "10XGEN");
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        usdt = IERC20(0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2);
        price = 10 * 10 ** 6;
        bankAddress = 0xC565FC29F6df239Fe3848dB82656F2502286E97d;
    }

    /**
     * @dev 公开 mint - 检查总供应量上限 + 钱包上限
     */
    function mint(uint256 quantity) external {
        require(quantity > 0, "Quantity must be > 0");
        require(
            mintedCount[msg.sender] + quantity <= MAX_PER_WALLET,
            "Exceeds max per wallet"
        );
        require(
            totalSupply + quantity <= MAX_TOTAL_SUPPLY,
            "Exceeds max total supply"
        ); // 新增总上限检查

        uint256 totalCost = price * quantity;
        require(totalCost > 0, "Price not set");

        // USDT 直接从用户转给 bankAddress
        usdt.safeTransferFrom(msg.sender, bankAddress, totalCost);

        uint256 startId = totalSupply + 1;
        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = startId + i;
            _safeMint(msg.sender, tokenId);
            emit Minted(msg.sender, tokenId, price);
        }

        mintedCount[msg.sender] += quantity;
        totalSupply += quantity;
    }

    /**
     * @dev 设置 mint 价格（onlyOwner）
     */
    function setPrice(uint256 newPrice) external onlyOwner {
        emit PriceUpdated(price, newPrice);
        price = newPrice;
    }

    function setPayToken(address payToken) external onlyOwner {
        require(payToken != address(0), "Invalid bank address");
        emit PayTokenUpdated(payToken);
        usdt = IERC20(payToken);
    }
    /**
     * @dev 设置统一图片 URI（onlyOwner）
     */
    function setBaseURI(string calldata newURI) external onlyOwner {
        emit BaseURIUpdated(baseURI, newURI);
        baseURI = newURI;
    }

    /**
     * @dev 设置新的收款银行地址（onlyOwner）
     */
    function setBankAddress(address newBank) external onlyOwner {
        require(newBank != address(0), "Invalid bank address");
        emit BankAddressUpdated(bankAddress, newBank);
        bankAddress = newBank;
    }

    /**
     * @dev 返回统一 metadata URI（所有 NFT 图片相同）
     */
    function tokenURI(
        uint256 /* tokenId */
    ) public view override returns (string memory) {
        require(totalSupply > 0, "URI query for nonexistent token"); // 至少有一个 token
        return baseURI;
    }

    // ============ 查看函数 ============
    function getBankAddress() external view returns (address) {
        return bankAddress;
    }

    // ============ UUPS 升级授权 ============
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
