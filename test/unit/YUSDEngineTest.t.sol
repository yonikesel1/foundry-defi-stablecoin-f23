// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployYUSD} from "../../script/DeployYUSD.s.sol";
import {YUSDEngine} from "../../src/YUSDEngine.sol";
import {YoniUSD} from "../../src/YoniUSD.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract YUSDEngineTest is Test {
    DeployYUSD deployer;
    YoniUSD yUSD;
    YUSDEngine yUSDengine;
    HelperConfig config;

    function setUp() public {
        deployer = new DeployYUSD();
        (yUSD, yUSDengine, config) = deployer.run();
    }

    function testGetAccountCollateralValueInUSD() public {}
}
