//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {YUSDEngine} from "../../src/YUSDEngine.sol";
import {YoniUSD} from "../../src/YoniUSD.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    YUSDEngine engine;
    YoniUSD yusd;
    ERC20Mock weth;
    ERC20Mock wbtc;
    MockV3Aggregator ethPriceFeed;

    uint256 public timesMintIsCalled;
    address[] public accountsWithCollateral;

    uint256 MAX_DEPOSIT_AMOUNT = type(uint96).max;

    constructor(YUSDEngine _engine, YoniUSD _yusd) {
        engine = _engine;
        yusd = _yusd;

        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(weth)));
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_AMOUNT);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        accountsWithCollateral.push(msg.sender);
    }

    function mintYUSD(uint256 amountYusdToMint, uint256 addressSeed) public {
        if (accountsWithCollateral.length == 0) return;
        address sender = accountsWithCollateral[addressSeed % accountsWithCollateral.length];
        (uint256 totalYUSDMinted, uint256 totalCollateralValueUSD) = engine.getAccountInformation(sender);
        int256 maxYUSDToMint = (int256(totalCollateralValueUSD) / 2) - int256(totalYUSDMinted);
        if (maxYUSDToMint < 0) return;
        amountYusdToMint = bound(amountYusdToMint, 0, uint256(maxYUSDToMint));
        if (amountYusdToMint == 0) return;
        vm.startPrank(sender);
        engine.mintYUSD(amountYusdToMint);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = engine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) return;

        vm.startPrank(msg.sender);
        engine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    function updateCollateralPrice(uint96 newPrice) public {
        ethPriceFeed.updateAnswer(int256(uint256(newPrice)));
    }

    // Helper Functions

    function getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
