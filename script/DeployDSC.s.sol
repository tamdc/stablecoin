// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenaddresses;
    address[] public priceFeeds;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address weth, address wbtc, address wethUsdPriceFeed, address wbtcUsdPriceFeed, uint256 deployKey) =
            config.activeNetworkConfig();
        tokenaddresses = [weth, wbtc];
        priceFeeds = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployKey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine dscEngine = new DSCEngine(tokenaddresses, priceFeeds, address(dsc));
        vm.stopBroadcast();
        return (dsc, dscEngine, config);
    }
}
    