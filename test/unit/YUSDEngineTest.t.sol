// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployYUSD} from "../../script/DeployYUSD.s.sol";
import {YUSDEngine} from "../../src/YUSDEngine.sol";
import {YoniUSD} from "../../src/YoniUSD.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

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
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployYUSD();
        (yUSD, yUSDengine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
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

    // function testDepositCollateral() public {
    //     uint256 amount = 15e18;
    //     uint256 actualUsd = yUSDengine.depositCollateral(weth, amount);
    //     assertEq(actualUsd, expectedUsd);
    // }
}
