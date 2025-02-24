// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of functions
// constructor
// receive function (if exists)
// fallback funtion (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.19;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStatbleCoin__MustBeMoreThanZero();
    error DecentralizedStatbleCoin__BurnAmountExceedsBalance();
    error DecentralizedStatbleCoin__NotZeroAddress();

    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStatbleCoin__MustBeMoreThanZero();
        }

        if (_amount > balance) {
            revert DecentralizedStatbleCoin__BurnAmountExceedsBalance();
        }

        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStatbleCoin__NotZeroAddress();
        }

        if (_amount <= 0) {
            revert DecentralizedStatbleCoin__MustBeMoreThanZero();
        }

        _mint(_to, _amount);
        return true;
    }
}
