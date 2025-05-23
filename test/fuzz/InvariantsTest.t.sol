// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DSCEngineHandler} from "./DSCEngineHandler.t.sol";

contract InvariantTest is StdInvariant, Test {
    DeployDSC deployer;
    HelperConfig config;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    DSCEngineHandler handler;
    address weth;
    address wbtc;
    address wethPriceFeed;
    address wbtcPriceFeed;
    uint256 private invariantCallCount;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (weth, wbtc,,,) = config.activeNetworkConfig();
        handler = new DSCEngineHandler(dsc, dsce, weth, wbtc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

        uint256 totalWethValue = dsce.getValueInUsd(weth, totalWethDeposited);
        uint256 totalWbtcValue = dsce.getValueInUsd(wbtc, totalWbtcDeposited);

        assert(totalWethValue + totalWbtcValue >= totalSupply);
    }
}
