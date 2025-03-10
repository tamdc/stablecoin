// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract TestDSCEngine is Test {
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    DeployDSC deployer;
    HelperConfig config;
    address weth;
    address wethPriceFeed;
    address public user = makeAddr('user');
    uint256 public constant AMOUNT_COLLATERAL = 20 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (weth,, wethPriceFeed,,) = config.activeNetworkConfig();
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////
    address[] public tokenAddresses;
    address[] public feedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {}

    //////////////////
    // Price Tests //
    //////////////////

    function testGetTokenAmountFromUsd() public {}

    function testGetUsdValue() public {
        // 15e18 * 2,000/ETH = 30,000e18
        uint256 amount = 15e18;
        uint256 expectedResult = 30_000e18;
        uint256 result = dsce.getValueInUsd(weth, amount);
        
        assertEq(expectedResult, result);
    }

    ///////////////////////////////////////
    // depositCollateral Tests //
    ///////////////////////////////////////

    // this test needs it's own setup
    function testRevertsIfTransferFromFails() public {}

    function testRevertsIfCollateralZero() public {
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        dsce.depositeCollateral(weth, 0);
    }

    function testRevertsWithUnapprovedCollateral() public {}

    modifier depositedCollateral() {
        _;
    }

    function testCanDepositCollateralWithoutMinting() public {}

    function testCanDepositedCollateralAndGetAccountInfo() public {}

    ///////////////////////////////////////
    // depositCollateralAndMintDsc Tests //
    ///////////////////////////////////////

    function testRevertsIfMintedDscBreaksHealthFactor() public {}

    modifier depositedCollateralAndMintedDsc() {
        _;
    }

    function testCanMintWithDepositedCollateral() public {}

    ///////////////////////////////////
    // mintDsc Tests //
    ///////////////////////////////////
    // This test needs it's own custom setup
    function testRevertsIfMintFails() public {}

    function testRevertsIfMintAmountIsZero() public {}

    function testRevertsIfMintAmountBreaksHealthFactor() public {}

    function testCanMintDsc() public {}

    ///////////////////////////////////
    // burnDsc Tests //
    ///////////////////////////////////

    function testRevertsIfBurnAmountIsZero() public {}

    function testCantBurnMoreThanUserHas() public {}

    function testCanBurnDsc() public {}

    ///////////////////////////////////
    // redeemCollateral Tests //
    //////////////////////////////////

    // this test needs it's own setup
    function testRevertsIfTransferFails() public {}

    function testRevertsIfRedeemAmountIsZero() public {}

    function testCanRedeemCollateral() public depositedCollateral {}

    function testEmitCollateralRedeemedWithCorrectArgs() public {}
    ///////////////////////////////////
    // redeemCollateralForDsc Tests //
    //////////////////////////////////

    function testMustRedeemMoreThanZero() public {}

    function testCanRedeemDepositedCollateral() public {}

    ////////////////////////
    // healthFactor Tests //
    ////////////////////////

    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc {}

    function testHealthFactorCanGoBelowOne() public {}

    ///////////////////////
    // Liquidation Tests //
    ///////////////////////

    // This test needs it's own setup
    function testMustImproveHealthFactorOnLiquidation() public {}

    function testCantLiquidateGoodHealthFactor() public {}

    modifier liquidated() {
        _;
    }

    function testLiquidationPayoutIsCorrect() public liquidated {}

    function testUserStillHasSomeEthAfterLiquidation() public liquidated {}

    function testLiquidatorTakesOnUsersDebt() public liquidated {}

    function testUserHasNoMoreDebt() public liquidated {}

    ///////////////////////////////////
    // View & Pure Function Tests //
    //////////////////////////////////
    function testGetCollateralTokenPriceFeed() public {}

    function testGetCollateralTokens() public {}

    function testGetMinHealthFactor() public {}

    function testGetLiquidationThreshold() public {}

    function testGetAccountCollateralValueFromInformation() public {}

    function testGetCollateralBalanceOfUser() public {}

    function testGetAccountCollateralValue() public {}

    function testGetDsc() public {}

    function testLiquidationPrecision() public {}
}
