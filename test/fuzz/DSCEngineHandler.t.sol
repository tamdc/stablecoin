//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {Test, console2} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract DSCEngineHandler is Test {
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    address weth;
    address wbtc;
    address[] users;
    uint256 constant MAX_USERS = 6;

    constructor(DecentralizedStableCoin _dsc, DSCEngine _dsce, address _weth, address _wbtc) {
        dsc = _dsc;
        dsce = _dsce;
        weth = _weth;
        wbtc = _wbtc;
    }

    function depositCollateral(address collateral, uint256 amountCollateral) public {
        uint256 userIndex = uint256(keccak256(abi.encode(amountCollateral)));
        collateral = chooseWethOrWbtc(amountCollateral);
        amountCollateral = bound(amountCollateral, 1e18, 1_000_000e18);
        address user = _getOrCreateUser(userIndex);
        vm.assume(user != address(0));

        vm.startPrank(user);
        ERC20Mock(collateral).mint(user, amountCollateral);
        ERC20Mock(collateral).approve(address(dsce), amountCollateral);
        try dsce.depositCollateral(collateral, amountCollateral) {
            console2.log("[depositCollateral] success with amount: ", amountCollateral);
        } catch {
            console2.log("(depositCollateral) reverted with amount: ", amountCollateral);
        }
        vm.stopPrank();
    }

    function mintDSC(uint256 amountDscToMint) public {
        uint256 userIndex = uint256(keccak256(abi.encode(amountDscToMint)));
        amountDscToMint = bound(amountDscToMint, 1, 1_000_000e18);
        address user = _getOrCreateUser(userIndex);
        vm.assume(user != address(0));
        vm.startPrank(user);
        try dsce.mintDSC(amountDscToMint) {
            console2.log("[mintDSC] success with amount: ", amountDscToMint);
        } catch {
            console2.log("(mintDSC) reverted with amount: ", amountDscToMint);
        }
        vm.stopPrank();
    }

    function burnDSC(uint256 amountDscToBurn) public {
        // get user
        uint256 userIndex = uint256(keccak256(abi.encode(amountDscToBurn)));
        address user = _getOrCreateUser(userIndex);
        vm.assume(user != address(0));
        (uint256 dscAmount,) = dsce.getAccountInformation(user);
        if (dscAmount == 0) return;

        amountDscToBurn = bound(amountDscToBurn, 1, dscAmount);
        vm.startPrank(user);
        try dsce.burnDSC(amountDscToBurn) {
            console2.log("[burnDSC] success with amount: ", amountDscToBurn);
        } catch {
            console2.log("(burnDSC) reverted with amount: ", amountDscToBurn);
        }
        vm.stopPrank();
    }

    function redeemCollateral(address collateralAddress, uint256 amountCollateral) public {
        collateralAddress = chooseWethOrWbtc(amountCollateral);

        uint256 userIndex = uint256(keccak256(abi.encode(amountCollateral)));
        address user = _getOrCreateUser(userIndex);
        vm.assume(user != address(0));
        uint256 collateralAmount = dsce.getCollateralAmount(collateralAddress, user);
        if (collateralAmount == 0) return;

        amountCollateral = bound(amountCollateral, 1, collateralAmount);

        vm.startPrank(user);
        try dsce.redeemCollateral(collateralAddress, amountCollateral) {
            console2.log("[redeemCollateral] success with amount: ", amountCollateral);
        } catch {
            console2.log("(redeemCollateral) reverted with amount: ", amountCollateral);
        }
        vm.stopPrank();
    }

    function liquidate(address collateralAddress, address user, uint256 debtToCover) public {
        collateralAddress = chooseWethOrWbtc(debtToCover);

        uint256 userIndex = uint256(keccak256(abi.encode(debtToCover)));
        user = _getOrCreateUser(userIndex);

        uint256 liquidatorIndex = uint256(keccak256(abi.encode(debtToCover, userIndex)));
        address liquidator = _getOrCreateUser(liquidatorIndex);
        (uint256 dscAmount,) = dsce.getAccountInformation(user);
        if (dscAmount == 0) return;
        debtToCover = bound(debtToCover, 1, dscAmount);

        vm.startPrank(liquidator);
        try dsce.liquidate(collateralAddress, user, debtToCover) {
            console2.log("[liquidate] success with amount: ", debtToCover);
        } catch {
            console2.log("(liquidate) reverted with amount: ", debtToCover);
        }
        vm.stopPrank();
    }

    // Helpers
    function chooseWethOrWbtc(uint256 input) public view returns (address) {
        return input % 2 == 0 ? weth : wbtc;
    }

    function _getOrCreateUser(uint256 userIndex) private returns (address user) {
        uint256 index = userIndex % MAX_USERS;
        console2.log("user: ", index);
        if (users.length == 0 || index > users.length - 1) {
            address newUser = vm.addr(uint256(keccak256(abi.encode(userIndex, block.timestamp))));
            users.push(newUser);
            return newUser;
        }
        return users[index];
    }

    function getUsers() public view returns (address[] memory) {
        return users;
    }

    function toE18(uint256 value) public pure returns (string memory) {
        uint256 tokenAmount = value / 1e18;
        string memory numberStr = Strings.toString(tokenAmount);
        return string(abi.encodePacked(numberStr, "e18"));
    }
}
