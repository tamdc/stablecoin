// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockAggregatorV3} from "test/mocks/MockAggregatorV3.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address weth;
        address wbtc;
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        uint256 deployKey;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_PRICE = 2_000 * 1e8;
    int256 public constant BTC_PRICE = 80_000 * 1e8;

    NetworkConfig public activeNetworkConfig;

    uint256 public constant ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaNetworkConfig();
        } else {
            activeNetworkConfig = getAnvilNetworkConfig();
        }
    }

    function getSepoliaNetworkConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            weth: 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9,
            wbtc: 0xb210fba65DC617bE30eB6B0b99B3CDd5556EF82e,
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            deployKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getAnvilNetworkConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.weth != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();

        MockAggregatorV3 wethPriceFeed = new MockAggregatorV3(DECIMALS, ETH_PRICE);
        ERC20Mock weth = new ERC20Mock();

        MockAggregatorV3 wbtcPriceFeed = new MockAggregatorV3(DECIMALS, BTC_PRICE);
        ERC20Mock wbtc = new ERC20Mock();

        vm.stopBroadcast();

        return NetworkConfig({
            weth: address(weth),
            wbtc: address(wbtc),
            wethUsdPriceFeed: address(wethPriceFeed),
            wbtcUsdPriceFeed: address(wbtcPriceFeed),
            deployKey: ANVIL_PRIVATE_KEY
        });
    }
}
