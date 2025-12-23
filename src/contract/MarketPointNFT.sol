// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MarketPointNFT is
    Initializable,
    ERC1155Upgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    uint256 public nextTokenId;
    uint256 public constant MINT_COST = 10 * 10 ** 6;
    uint256 public constant POINTS_PER_MINT = 100;

    address public USDT_ADDRESS;
    address public BANK_ADDRESS;

    IERC20 public usdt;
    string public baseURI;

    event UpdatePrizePoolAddress(address indexed newAddress);
    event UpdatePayAddress(address indexed newAddress);
    event Minted(address indexed user, uint256[] tokenIds, uint256 amount, uint256 totalPoints);
    event EmergencyWithdraw(address indexed recipient, address indexed token, uint256 amount);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _usdt,
        string memory _uri
    ) external initializer {
        __ERC1155_init(_uri);
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        USDT_ADDRESS = _usdt;
        BANK_ADDRESS = 0xC565FC29F6df239Fe3848dB82656F2502286E97d;
        usdt = IERC20(USDT_ADDRESS);
        baseURI = _uri;
    }

    function setPayToken(address _erc20TokenAddress) external onlyOwner {
        require(_erc20TokenAddress != address(0), "Invalid address");
        USDT_ADDRESS = _erc20TokenAddress;
        usdt = IERC20(_erc20TokenAddress);
        emit UpdatePayAddress(_erc20TokenAddress);
    }

    function setPrizePoolAddress(address _bankAddress) external onlyOwner {
        require(_bankAddress != address(0), "Invalid address");
        BANK_ADDRESS = _bankAddress;
        emit UpdatePrizePoolAddress(_bankAddress);
    }

    function mint(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        require(amount <= 100, "Max 100 per tx");

        uint256 totalCost = amount * MINT_COST;

        usdt.safeTransferFrom(msg.sender, address(this), totalCost);

        uint256[] memory tokenIds = new uint256[](amount);
        uint256[] memory amounts = new uint256[](amount);

        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenId = ++nextTokenId;
            tokenIds[i] = tokenId;
            amounts[i] = 1;
        }

        _mintBatch(msg.sender, tokenIds, amounts, "");

        uint256 totalPoints = amount * POINTS_PER_MINT;

        emit Minted(msg.sender, tokenIds, amount, totalPoints);
    }


    function safeTransferFrom(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public pure override {
        revert("Transfers disabled");
    }

    function safeBatchTransferFrom(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public pure override {
        revert("Transfers disabled");
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function uri(uint256) public view override returns (string memory) {
        return baseURI;
    }

    receive() external payable {}

    function emergencyWithdraw(
        address recipient,
        address token,
        uint256 amount
    ) external onlyOwner {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be > 0");

        if (token == address(0)) {
            (bool success, ) = payable(recipient).call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(recipient, amount);
        }

        emit EmergencyWithdraw(recipient, token, amount);
    }
}