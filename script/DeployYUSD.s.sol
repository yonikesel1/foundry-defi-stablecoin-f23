// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {YoniUSD} from "../src/YoniUSD.sol";
import {YUSDEngine} from "../src/YUSDEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployYUSD is Script {
    address[] public collateralTokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (YoniUSD, YUSDEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address wethUSDPriceFeed, address wbtcUSDPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            config.activeNetworkConfig();
        collateralTokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUSDPriceFeed, wbtcUSDPriceFeed];
        vm.startBroadcast(deployerKey);
        YoniUSD yusd = new YoniUSD();
        YUSDEngine engine = new YUSDEngine(address(yusd), collateralTokenAddresses, priceFeedAddresses);
        yusd.transferOwnership(address(engine));
        vm.stopBroadcast();

        return (yusd, engine, config);
    }
}
