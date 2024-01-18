// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployYUSD} from "../../script/DeployYUSD.s.sol";
import {YUSDEngine} from "../../src/YUSDEngine.sol";
import {YoniUSD} from "../../src/YoniUSD.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract YUSDEngineTest is Test {
    DeployYUSD deployer;
    YoniUSD yUSD;
    YUSDEngine yUSDengine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant LIQUIDATOR_STARTIG_BALANCE = 10000 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployYUSD();
        (yUSD, yUSDengine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, LIQUIDATOR_STARTIG_BALANCE);
    }

    ////////////////////////////
    // Constructor Tests      //
    ////////////////////////////
    address[] public tokenAddress;
    address[] public priceFeedAddress;

    function testRevertIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddress.push(weth);
        priceFeedAddress.push(ethUsdPriceFeed);
        priceFeedAddress.push(btcUsdPriceFeed);
        vm.expectRevert(YUSDEngine.YUSDEngine__TokenAddressesAndPriceFeedAddresesMustBeSameLength.selector);
        new YUSDEngine(address(yUSD), tokenAddress, priceFeedAddress);
    }

    //////////////////////
    // Price Tests      //
    //////////////////////

    function testGetUSDValue() public {
        uint256 amount = 15e18;
        uint256 expectedUsd = 30_000e18;
        uint256 actualUsd = yUSDengine.getUSDValue(weth, amount);
        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 amount = 2000e18;
        uint256 expectedTokenAmount = 1e18;
        uint256 actualTokenAmount = yUSDengine.getTokenAmountFromUsd(weth, amount);
        assertEq(actualTokenAmount, expectedTokenAmount);
    }

    ///////////////////////////////////
    // Deposit Collateral Tests      //
    ///////////////////////////////////

    function testRevertIfCollateralZero() public {
        uint256 amount = 0;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(yUSDengine), AMOUNT_COLLATERAL);
        vm.expectRevert(YUSDEngine.YUSDEngine__NeedsMoreThanZero.selector);
        yUSDengine.depositCollateral(weth, amount);
        vm.stopPrank();
    }

    function testRevertIfCollateralTokenNotAllowed() public {
        ERC20Mock newMock = new ERC20Mock();
        uint256 amount = 2000e18;
        vm.startPrank(USER);
        vm.expectRevert(YUSDEngine.YUSDEngine__CollateralTokenNotAllowed.selector);
        yUSDengine.depositCollateral(address(newMock), amount);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(yUSDengine), AMOUNT_COLLATERAL);
        yUSDengine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalYUSDMinted, uint256 totalCollateralValueUSD) = yUSDengine.getAccountInformation(USER);
        assertEq(totalCollateralValueUSD, yUSDengine.getUSDValue(address(weth), AMOUNT_COLLATERAL));
        assertEq(totalYUSDMinted, 0);
    }

    //////////////////////////
    // Mint YUSD Tests      //
    //////////////////////////

    modifier mintYUSD(uint256 amountYUSDToMint) {
        vm.startPrank(USER);
        yUSDengine.mintYUSD(amountYUSDToMint);
        vm.stopPrank();
        _;
    }

    function testMintYUSDAndGetAccountInfo() public depositedCollateral mintYUSD(1000e18) {
        (uint256 totalYUSDMinted, uint256 totalCollateralValueUSD) = yUSDengine.getAccountInformation(USER);
        assertEq(totalCollateralValueUSD, yUSDengine.getUSDValue(address(weth), AMOUNT_COLLATERAL));
        assertEq(totalYUSDMinted, 1000e18);
    }

    function testMintYUSDAndCheckHealth() public depositedCollateral mintYUSD(10000e18) {
        uint256 healthFactor = yUSDengine.getHealthFactor(USER);
        uint256 expectedHealthFactor = 1e4;
        assertEq(healthFactor, expectedHealthFactor);
    }

    function testDepositCollateralAndMintUsd() public {
        uint256 amountYUSDToMint = 1000e18;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(yUSDengine), AMOUNT_COLLATERAL);
        yUSDengine.depositCollateralAndMintYUSD(address(weth), AMOUNT_COLLATERAL, amountYUSDToMint);
        vm.stopPrank();
        (uint256 totalYUSDMinted, uint256 totalCollateralValueUSD) = yUSDengine.getAccountInformation(USER);
        assertEq(totalCollateralValueUSD, yUSDengine.getUSDValue(address(weth), AMOUNT_COLLATERAL));
        assertEq(totalYUSDMinted, amountYUSDToMint);
    }

    function testRevertIfBreaksHealthFactor() public depositedCollateral {
        uint256 amountYUSDToMint = 10001e18;
        uint256 expectedHealth = 9999;
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(YUSDEngine.YUSDEngine__BreaksHealthFactor.selector, expectedHealth));
        yUSDengine.mintYUSD(amountYUSDToMint);
        vm.stopPrank();
    }

    //////////////////////////
    // Burn YUSD Tests      //
    //////////////////////////

    modifier burnYUSD(uint256 amountYUSDToBurn) {
        vm.startPrank(USER);
        yUSD.approve(address(yUSDengine), amountYUSDToBurn);
        yUSDengine.burnYUSD(amountYUSDToBurn);
        vm.stopPrank();
        _;
    }

    function testRevertIfBurnMoreThanMinted() public depositedCollateral mintYUSD(1000e18) {
        uint256 amountYUSDToBurn = 1001e18;
        vm.startPrank(USER);
        vm.expectRevert(YUSDEngine.YUSDEngine__BurnMoreThanMinted.selector);
        yUSDengine.burnYUSD(amountYUSDToBurn);
        vm.stopPrank();
    }

    function testBurnYUSDAndGetAccountInfo() public depositedCollateral mintYUSD(1000e18) burnYUSD(500e18) {
        (uint256 totalYUSDMinted,) = yUSDengine.getAccountInformation(USER);
        assertEq(totalYUSDMinted, 500e18);
    }

    ///////////////////////
    // Redeem Tests      //
    ///////////////////////

    modifier redeemCollateral(address collateralToRedeem, uint256 amountCollateralToRedeem) {
        vm.startPrank(USER);
        yUSDengine.redeemCollateral(collateralToRedeem, amountCollateralToRedeem);
        vm.stopPrank();
        _;
    }

    modifier redeemCollateralAndMintYUSD() {
        uint256 amountYUSDToMint = 10000e18;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(yUSDengine), AMOUNT_COLLATERAL);
        yUSDengine.depositCollateralAndMintYUSD(weth, AMOUNT_COLLATERAL, amountYUSDToMint);
        vm.stopPrank();
        _;
    }

    function testRevertIfRedeemZero() public {
        uint256 amountCollateralToRedeem = 0;
        vm.startPrank(USER);
        vm.expectRevert(YUSDEngine.YUSDEngine__NeedsMoreThanZero.selector);
        yUSDengine.redeemCollateral(weth, amountCollateralToRedeem);
        vm.stopPrank();
    }

    function testRevertIfRedeemMoreThanSupplied() public depositedCollateral {
        uint256 amountCollateralToRedeem = 11 ether;
        vm.startPrank(USER);
        vm.expectRevert(YUSDEngine.YUSDEngine__CantRedeemMoreThanSupplied.selector);
        yUSDengine.redeemCollateral(weth, amountCollateralToRedeem);
        vm.stopPrank();
    }

    function testRevertIfRedeemBreaksHealthFactor() public redeemCollateralAndMintYUSD {
        uint256 amountCollateralToRedeem = 1 ether;
        uint256 expectedHealth = 9000;
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(YUSDEngine.YUSDEngine__BreaksHealthFactor.selector, expectedHealth));
        yUSDengine.redeemCollateral(weth, amountCollateralToRedeem);
        vm.stopPrank();
    }

    function testRedeemCollateral() public depositedCollateral {
        uint256 balanceBeforeRedeem = ERC20Mock(weth).balanceOf(USER);
        vm.startPrank(USER);
        yUSDengine.redeemCollateral(weth, 5 ether);
        vm.stopPrank();
        uint256 balanceAfterRedeem = ERC20Mock(weth).balanceOf(USER);
        (, uint256 totalCollateralValueUSD) = yUSDengine.getAccountInformation(USER);
        assertEq(totalCollateralValueUSD, yUSDengine.getUSDValue(address(weth), AMOUNT_COLLATERAL - 5 ether));
        assertEq(balanceAfterRedeem, balanceBeforeRedeem + 5 ether);
    }

    function testRedeemCollateralForYUSD() public redeemCollateralAndMintYUSD {
        uint256 amountUsdToBurn = 10000e18;
        vm.startPrank(USER);
        yUSD.approve(address(yUSDengine), amountUsdToBurn);
        yUSDengine.redeemCollateralForYUSD(weth, AMOUNT_COLLATERAL, amountUsdToBurn);
        vm.stopPrank();
        uint256 yUSDBalanceAfterRedeem = yUSD.balanceOf(USER);
        (uint256 totalYUSDMinted, uint256 totalCollateralValueUSD) = yUSDengine.getAccountInformation(USER);
        assertEq(totalYUSDMinted, 0);
        assertEq(totalCollateralValueUSD, 0);
        assertEq(yUSDBalanceAfterRedeem, 0);
    }

    ///////////////////////
    // Liquidation Tests //
    ///////////////////////

    modifier liquidatorDepositAndMintYUSD() {
        uint256 amountYUSDToMint = 50000e18;
        uint256 liquidatorDepositAmount = 5000 ether;
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(yUSDengine), liquidatorDepositAmount);
        yUSDengine.depositCollateralAndMintYUSD(weth, liquidatorDepositAmount, amountYUSDToMint);
        vm.stopPrank();
        _;
    }

    function testRevertIfAmountZero() public liquidatorDepositAndMintYUSD depositedCollateral mintYUSD(1000e18) {
        uint256 debtToCover = 0;
        vm.startPrank(USER);
        vm.expectRevert(YUSDEngine.YUSDEngine__NeedsMoreThanZero.selector);
        yUSDengine.liquidate(weth, USER, debtToCover);
        vm.stopPrank();
    }

    function testRevertIfHealthFactorOK() public liquidatorDepositAndMintYUSD depositedCollateral mintYUSD(1000e18) {
        uint256 debtToCover = 1000e18;
        vm.startPrank(USER);
        vm.expectRevert(YUSDEngine.YUSDEngine__HealthFactorOK.selector);
        yUSDengine.liquidate(weth, USER, debtToCover);
        vm.stopPrank();
    }

    function testLiquidate() public liquidatorDepositAndMintYUSD depositedCollateral mintYUSD(10000e18) {
        uint256 debtToCover = 5000e18;
        uint256 wethBalanceOfLiquidatorAfterLiquidationBefore = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1000e8);
        vm.startPrank(LIQUIDATOR);
        yUSD.approve(address(yUSDengine), debtToCover);
        yUSDengine.liquidate(weth, USER, debtToCover);
        vm.stopPrank();
        uint256 wethBalanceOfLiquidatorAfterLiquidationAfter = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        uint256 expectedLiquidatorBonusAfterLiquidation = 55e17;
        assertEq(
            wethBalanceOfLiquidatorAfterLiquidationAfter - wethBalanceOfLiquidatorAfterLiquidationBefore,
            expectedLiquidatorBonusAfterLiquidation
        );
    }
}
