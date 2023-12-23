// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {YoniUSD} from "./YoniUSD.sol";
import {AggregatorV3Interface} from
    "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "forge-std/console.sol";

/*
* @title YUSDEngine
* @author YoniKesel
* 
* Designed to be as minimal as possible, and keep the peg of 1$
* Properties of YUSD:
* - Overcollateralized
* - USD Pegged
* - Collateral: WETH and WBTC
* - Algorithmically Stable
*
* @notice This contract is the core of the YUSD stablecoin. It handles all the logic for minting and redeeming YUSD,
* as well as depositing and withdrawing collateral
* @notice This contract is based on MakerDAO DAI System
*/

contract YUSDEngine is ReentrancyGuard {
    /////////////////
    // Errors      //
    /////////////////
    error YUSDEngine__NeedsMoreThanZero();
    error YUSDEngine__TokenAddressesAndPriceFeedAddresesMustBeSameLength();
    error YUSDEngine__CollateralTokenNotAllowed();
    error YUSDEngine__TransferFailed();
    error YUSDEngine__BreaksHealthFactor(uint256 userHealthFactor);
    error YUSDEngine__MintFailed();
    error YUSDEngine__BurnFailed();
    error YUSDEngine__BurnMoreThanMinted();

    //////////////////////////
    // State Variables      //
    //////////////////////////

    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_THRESHOLD_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address token => uint256 amountYUSDMinted) private s_YUSDMinted;
    address[] private s_collateralTokens;

    YoniUSD private immutable i_yusd;

    /////////////////
    // Events      //
    /////////////////

    event collateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event collateralRedeemed(address indexed user, address indexed token, uint256 indexed amount);

    /////////////////
    // Modifiers   //
    /////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert YUSDEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedCollateralToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert YUSDEngine__CollateralTokenNotAllowed();
        }
        _;
    }

    /////////////////
    // Functions   //
    /////////////////

    constructor(address YUSDAddress, address[] memory collateralTokenAddresses, address[] memory priceFeedsAddresses) {
        if (collateralTokenAddresses.length != priceFeedsAddresses.length) {
            revert YUSDEngine__TokenAddressesAndPriceFeedAddresesMustBeSameLength();
        }

        for (uint256 i = 0; i < collateralTokenAddresses.length; i++) {
            s_priceFeeds[collateralTokenAddresses[i]] = priceFeedsAddresses[i];
            s_collateralTokens.push(collateralTokenAddresses[i]);
        }

        i_yusd = YoniUSD(YUSDAddress);
    }

    //////////////////////////
    // External Functions   //
    //////////////////////////

    /*
    * @notice Deposit Collateral and Mint YUSD
    * @param tokenCollateralAddress The address of the token to deposit as collateral
    * @param amountCollateral The amount of collateral to deposit
    * @param amountYUSDToMint The amount of YUSD to mint
    * @notice deposit collateral and mint YUSD in a single transaction
    */
    function depositCollateralAndMintYUSD(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountYUSDToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintYUSD(amountYUSDToMint);
    }

    /* 
    * @notice Deposit Collateral
    * @dev Follows CEI
    * @param tokenCollateral The address of the token to deposit as collateral
    * @param amountCollateral The amount of collateral to deposit
    */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedCollateralToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);

        if (!success) {
            revert YUSDEngine__TransferFailed();
        }
        emit collateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
    }

    /*
    * @notice Redeem Collateral and Burn YUSD
    * @param tokenCollateralAddress The address of the token to redeem as collateral
    * @param amountCollateral The amount of collateral to redeem
    * @param amountYUSDToMint The amount of YUSD to burn
    * @notice redeem collateral and burn YUSD in a single transaction
    */
    function redeemCollateralForYUSD(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountYusdToBurn)
        external
    {
        burnYUSD(amountYusdToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    /* 
    * @notice Redeem Collateral
    * @dev Follows CEI
    * @param tokenCollateral The address of the token to redeem as collateral
    * @param amountCollateral The amount of collateral to redeem
    */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] -= amountCollateral;

        bool success = IERC20(tokenCollateralAddress).transferFrom(address(this), msg.sender, amountCollateral);
        if (!success) {
            revert YUSDEngine__TransferFailed();
        }
        _refertIfHealthFactorIsBroken(msg.sender);
        emit collateralRedeemed(msg.sender, tokenCollateralAddress, amountCollateral);
    }

    /* 
    * @notice Mint YUSD. Must have more collateral valure than the minimum threshold
    * @dev Follows CEI
    * @param amountYusdToMint The amount of YUSD to mint
    */
    function mintYUSD(uint256 amountYusdToMint) public moreThanZero(amountYusdToMint) nonReentrant {
        s_YUSDMinted[msg.sender] += amountYusdToMint;
        _refertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_yusd.mint(msg.sender, amountYusdToMint);
        if (!minted) {
            revert YUSDEngine__MintFailed();
        }
    }

    /* 
    * @notice Burn YUSD. Must have more collateral valure than the minimum threshold
    * @dev Follows CEI
    * @param amountYusdToMint The amount of YUSD to mint
    */
    function burnYUSD(uint256 amountYusdToBurn) public moreThanZero(amountYusdToBurn) nonReentrant {
        if (amountYusdToBurn > s_YUSDMinted[msg.sender]) {
            revert YUSDEngine__BurnMoreThanMinted();
        }
        s_YUSDMinted[msg.sender] -= amountYusdToBurn;

        bool success = i_yusd.transferFrom(msg.sender, address(this), amountYusdToBurn);
        if (!success) {
            revert YUSDEngine__TransferFailed();
        }

        i_yusd.burn(amountYusdToBurn);
        _refertIfHealthFactorIsBroken(msg.sender); // probably wont ever hit
    }

    function liquidate() external {}

    function getHealthFactor() external view {}

    /////////////////////////////////////////
    // Public & External View Functions    //
    /////////////////////////////////////////

    function getAccountCollateralValueInUSD(address user) public view returns (uint256 totalCollateralValueUSD) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueUSD += getUSDValue(token, amount);
        }
        return totalCollateralValueUSD;
    }

    function getUSDValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint8 feedDecimals = priceFeed.decimals();
        uint8 tokenDecimals = ERC20(token).decimals();
        uint8 diffDecimals = tokenDecimals - feedDecimals;
        return (amount * (uint256(price) * (10 ** diffDecimals))) / (10 ** tokenDecimals);
    }

    /////////////////////////////////////////
    // Private & Internal View Functions   //
    /////////////////////////////////////////

    /* 
    * @notice Calculates the current health factor of the user
    * @dev Follows CEI
    * @param user The user to get the current health factor
    * @returns The user Health Factor
    */
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalYUSDMinted, uint256 totalCollateralValueUSD)
    {
        totalYUSDMinted = s_YUSDMinted[user];
        totalCollateralValueUSD = getAccountCollateralValueInUSD(user);
    }

    /* 
    * @notice Calculates the current health factor of the user
    * @dev Follows CEI
    * @param user The user to get the current health factor
    * @returns The user Health Factor
    */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalYUSDMinted, uint256 totalCollateralValueUSD) = _getAccountInformation(user);
        return (totalCollateralValueUSD * (LIQUIDATION_THRESHOLD / LIQUIDATION_THRESHOLD_PRECISION)) / totalYUSDMinted;
    }

    function _refertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert YUSDEngine__BreaksHealthFactor(userHealthFactor);
        }
    }
}
