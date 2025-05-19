//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {Test, console2} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MockAggregatorV3} from "test/mocks/MockAggregatorV3.sol";

contract DSCEngineHandler is Test {
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    address weth;
    address wbtc;
    address wethPriceFeed;
    address wbtcPriceFeed;
    address[] users;
    uint256 constant MAX_USERS = 6;
    uint256 constant INITIAL_WETH_PRICE = 2000e8; // $2000
    uint256 constant INITIAL_WBTC_PRICE = 80000e8; // $80,000

    constructor(DecentralizedStableCoin _dsc, DSCEngine _dsce, address _weth, address _wbtc) {
        dsc = _dsc;
        dsce = _dsce;
        weth = _weth;
        wbtc = _wbtc;
        wethPriceFeed = dsce.getCollateralTokenPriceFeed(weth);
        wbtcPriceFeed = dsce.getCollateralTokenPriceFeed(wbtc);
    }

    function depositCollateral(address collateral, uint256 amountCollateral) public {
        collateral = chooseWethOrWbtc(amountCollateral);
        amountCollateral = bound(amountCollateral, 1e18, 1_000_000e18); // 1 to 1M ether
        address user = _getOrCreateUser(uint256(keccak256(abi.encode(amountCollateral))));
        vm.assume(user != address(0));
        vm.startPrank(user);
        ERC20Mock(collateral).mint(user, amountCollateral);
        ERC20Mock(collateral).approve(address(dsce), amountCollateral);
        try dsce.depositCollateral(collateral, amountCollateral) {
            console2.log("[depositCollateral] Token: ", collateral, " Amount: ", amountCollateral);
        } catch Error(string memory reason) {
            console2.log("(depositCollateral) Reverted: ", reason);
        }
        vm.stopPrank();
    }

    function mintDSC(uint256 amountDscToMint) public {
        uint256 userIndex = uint256(keccak256(abi.encode(amountDscToMint)));
        address user = _getOrCreateUser(userIndex);
        vm.assume(user != address(0));
        (uint256 currentDscMinted, uint256 collateralValue) = dsce.getAccountInformation(user);
        if (collateralValue == 0) return;

        uint256 maxDsc = (collateralValue * dsce.getLiquidationThreshold()) / dsce.getLiquidationPrecision();
        uint256 remainingDscCapacity = maxDsc > currentDscMinted ? maxDsc - currentDscMinted : 0;
        amountDscToMint = bound(amountDscToMint, 0, remainingDscCapacity * 90 / 100); // 90% of max
        if (amountDscToMint == 0) return;

        vm.startPrank(user);
        try dsce.mintDSC(amountDscToMint) {
            console2.log("[mintDSC] Amount: ", amountDscToMint);
        } catch (bytes memory lowLevelData) {
            // Decode custom error DSCEngine__ReachLiquidationThreshold(uint256)
            if (lowLevelData.length >= 4) {
                bytes4 selector = bytes4(lowLevelData);
                if (selector == bytes4(keccak256("DSCEngine__ReachLiquidationThreshold(uint256)"))) {
                    (uint256 healthFactor) = abi.decode(slice(lowLevelData, 4, lowLevelData.length), (uint256));
                    console2.log(
                        "(mintDSC) Reverted: DSCEngine__ReachLiquidationThreshold, HealthFactor: ", healthFactor
                    );
                } else {
                    console2.log("(mintDSC) Reverted: Unknown error");
                }
            } else {
                console2.log("(mintDSC) Reverted: Invalid error data");
            }
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

        amountDscToBurn = bound(amountDscToBurn, 0, dscAmount);
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

        amountCollateral = bound(amountCollateral, 0, collateralAmount);

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

        if (user == address(0) || dsce.getHealthFactor(user) >= dsce.getMinHealthFactor()) {
            (user, collateralAddress) = _findLiquidableUser();
            if (user == address(0)) return; // No liquidatable users
        }
        (uint256 dscAmount,) = dsce.getAccountInformation(user);
        if (dscAmount == 0) return;
        debtToCover = bound(debtToCover, 1, dscAmount);

        uint256 liquidatorIndex = uint256(keccak256(abi.encode(debtToCover, block.timestamp)));
        address liquidator = _getOrCreateUser(liquidatorIndex);

        vm.startPrank(liquidator);
        ERC20Mock(collateralAddress).mint(liquidator, 1_000_000e18);
        ERC20Mock(collateralAddress).approve(address(dsce), 1_000_000e18);
        dsce.depositCollateral(collateralAddress, 1_000_000e18);
        (uint256 currentDscMinted, uint256 collateralValue) = dsce.getAccountInformation(liquidator);
        uint256 maxDsc = (collateralValue * dsce.getLiquidationThreshold()) / dsce.getLiquidationPrecision();

        uint256 remainingDscCapacity = maxDsc > currentDscMinted ? maxDsc - currentDscMinted : 0;
        if (remainingDscCapacity == 0) return;
        remainingDscCapacity = bound(remainingDscCapacity, 1, remainingDscCapacity * 90 / 100); // 90% of max

        dsce.mintDSC(remainingDscCapacity);
        dsc.approve(address(dsce), debtToCover);

        try dsce.liquidate(collateralAddress, user, debtToCover) {
            console2.log("[liquidate] success with amount: ", debtToCover);
        } catch {
            console2.log("(liquidate) reverted with amount: ", debtToCover);
        }
        vm.stopPrank();
    }

    function updatePriceFeed(uint256 price) public {
        address tokenAddress = price % 2 == 0 ? wethPriceFeed : wbtcPriceFeed;
        if (tokenAddress == wethPriceFeed) {
            price = bound(price, INITIAL_WETH_PRICE * 50 / 100, INITIAL_WETH_PRICE * 150 / 100);
        } else {
            price = bound(price, INITIAL_WBTC_PRICE * 50 / 100, INITIAL_WBTC_PRICE * 150 / 100);
        }
        MockAggregatorV3(tokenAddress).updateAnswer(int256(price));
    }

    // Helpers
    function chooseWethOrWbtc(uint256 input) public view returns (address) {
        return input % 2 == 0 ? weth : wbtc;
    }

    function _getOrCreateUser(uint256 userIndex) private returns (address user) {
        uint256 index = userIndex % MAX_USERS;
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

    function slice(bytes memory data, uint256 start, uint256 length) internal pure returns (bytes memory) {
        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = data[start + i];
        }
        return result;
    }

    function _findLiquidableUser() private view returns (address, address) {
        for (uint256 i = 0; i < users.length; i++) {
            address currentUser = users[i];
            if (dsce.getHealthFactor(currentUser) < dsce.getMinHealthFactor()) {
                for (uint256 j = 0; j < dsce.getCollateralTokens().length; j++) {
                    if (dsce.getCollateralAmount(dsce.getCollateralTokens()[j], currentUser) > 0) {
                        return (currentUser, dsce.getCollateralTokens()[j]);
                    }
                }
            }
        }
        return (address(0), address(0));
    }
}
