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

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
* @title YoniUSD
* @author YoniKesel
* Collateral: WETH & WBTC
* Minting: Algorithmic
* Relative Stability: Pegged to USD
* This contract is governed by YUSDEngine. This contract is the ERC20 of the stablecoin.
*/
contract YoniUSD is ERC20Burnable, Ownable {
    error YoniUSD_MustBeMoreThanZero();
    error YoniUSD_BurnAmountExceedsBalance();
    error YoniUSD_NotZeroAddress();

    constructor() ERC20("YoniUSD", "YUSD") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount < 0) {
            revert YoniUSD_MustBeMoreThanZero();
        }
        if (_amount < balance) {
            revert YoniUSD_BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert YoniUSD_NotZeroAddress();
        }
        if (_amount < 0) {
            revert YoniUSD_MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
