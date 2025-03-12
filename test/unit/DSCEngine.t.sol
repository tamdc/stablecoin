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
    address wbtc;
    address wethPriceFeed;
    address wbtcPriceFeed;
    address public user = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant LIQUIDATION_THRESHOLD = 50; // The maximum your DSC you can mint is 50% your total collatral
    uint256 public constant LIQUIDATION_PRECISION = 100;
    uint256 public constant LIQUIDATION_BONUS = 10;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant ADDITION_FEED_PRECISION = 1e10;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (weth, wbtc, wethPriceFeed, wbtcPriceFeed,) = config.activeNetworkConfig();

        vm.deal(user, STARTING_ERC20_BALANCE);
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethPriceFeed];

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    //////////////////
    // Price Tests //
    //////////////////

    function testGetTokenAmountFromUsd() public view {
        uint256 usd = 8_000 * PRECISION;
        uint256 expecedEthAmount = 4 * PRECISION;
        uint256 expectedBtcAmount = 1e17;

        uint256 ethAmount = dsce.tokenAmountFromUsdValue(weth, usd);
        uint256 btcAmount = dsce.tokenAmountFromUsdValue(wbtc, usd);

        assertEq(ethAmount, expecedEthAmount);
        assertEq(btcAmount, expectedBtcAmount);
    }

    function testGetUsdValue() public view {
        // 15e18 * 2,000/ETH = 30,000e18
        uint256 amount = 15e18;
        uint256 expectedResult = 30_000e18;
        uint256 result = dsce.getValueInUsd(weth, amount);

        assertEq(result, expectedResult);
    }

    ///////////////////////////////////////
    // depositCollateral Tests //
    ///////////////////////////////////////

    // this test needs it's own setup
    function testRevertsIfTransferFromFails() public {
        vm.prank(user);
        vm.expectRevert();
        dsce.depositeCollateral(weth, STARTING_ERC20_BALANCE);
    }

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

    function testGetMinHealthFactor() public view {
        uint256 minHealthFactor = dsce.getMinHealthFactor();
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
    }

    function testGetLiquidationThreshold() public view {
        uint256 liquidationThreshold = dsce.getLiquidationThreshold();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    function testGetAccountCollateralValueFromInformation() public {}

    function testGetCollateralBalanceOfUser() public {}

    function testGetAccountCollateralValue() public {}

    function testGetDsc() public {}

    function testLiquidationPrecision() public view {
        uint256 liquidationPrecision = dsce.getLiquidationPrecision();
        assertEq(liquidationPrecision, LIQUIDATION_PRECISION);
    }

    function testGetLiquidationBonus() public view {
        uint256 liquidationBonus = dsce.getLiquidationBonus();
        assertEq(liquidationBonus, LIQUIDATION_BONUS);
    }

    function testGetPrecision() public view {
        uint256 precision = dsce.getPrecision();
        assertEq(precision, PRECISION);
    }

    function testGetAdditionFeedPrecision() public view {
        uint256 additionFeedPrecision = dsce.getAdditionFeedPrecision();
        assertEq(additionFeedPrecision, ADDITION_FEED_PRECISION);
    }
}
