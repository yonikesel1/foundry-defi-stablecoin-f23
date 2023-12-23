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

    function depositCollateralAndMintYUSD() external {}

    /* 
    * @notice Deposit Collateral
    * @dev Follows CEI
    * @param tokenCollateral The address of the token to deposit as collateral
    * @param amountCollateral The amount of collateral to deposit
    * @return
    */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedCollateralToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit collateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);

        if (!success) {
            revert YUSDEngine__TransferFailed();
        }
    }

    function redeemCollateralForYUSD() external {}

    function redeemCollateral() external {}

    /* 
    * @notice Mint YUSD. Must have more collateral valure than the minimum threshold
    * @dev Follows CEI
    * @param amountYusdToMint The amount of YUSD to mint
    * @return
    */
    function mintYUSD(uint256 amountYusdToMint) external moreThanZero(amountYusdToMint) nonReentrant {
        s_YUSDMinted[msg.sender] += amountYusdToMint;
        _refertIfHealthFactorIsBroken(msg.sender);
    }

    function burnYUSD() external {}

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
        // 1e8
        // 1e18
        //
        return (amount * (uint256(price) * diffDecimals)) / tokenDecimals;
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
