// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Test, console2} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockAggregatorV3} from "test/mocks/MockAggregatorV3.sol";

contract TestDSCEngine is Test {
    DecentralizedStableCoin public dsc;
    DSCEngine public dsce;
    DeployDSC public deployer;
    HelperConfig public config;

    address public weth;
    address public wbtc;
    address public wethPriceFeed;
    address public wbtcPriceFeed;

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 5 ether;
    address public user = makeAddr("user");

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
        ERC20Mock(weth).mint(user, STARTING_ERC20_BALANCE);
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
        address owner = msg.sender;

        vm.startPrank(owner);
        ERC20Mock collateralToken = new ERC20Mock();
        collateralToken.mint(user, 20 ether);
        tokenAddresses.push(address(collateralToken));
        priceFeedAddresses.push(wethPriceFeed);
        DSCEngine dsce1 = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        vm.stopPrank();

        vm.startPrank(user);
        collateralToken.approve(address(dsce1), 0);
        vm.expectRevert();
        dsce1.depositeCollateral(address(collateralToken), amountCollateral);
        vm.stopPrank();
    }

    function testRevertsIfCollateralZero() public {
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        dsce.depositeCollateral(weth, 0);
    }

    function testRevertsWithUnapprovedCollateral() public {
        address owner = msg.sender;

        vm.startBroadcast(owner);
        ERC20Mock collateralContract = new ERC20Mock();
        collateralContract.mint(user, 20 ether);
        tokenAddresses.push(address(collateralContract));
        priceFeedAddresses.push(weth);
        DSCEngine dsce1 = new DSCEngine(tokenAddresses, priceFeedAddresses, address(wethPriceFeed));
        vm.stopBroadcast();

        vm.startBroadcast();
        vm.expectRevert();
        dsce1.depositeCollateral(address(collateralContract), 1 ether);
        vm.stopBroadcast();
    }

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositeCollateral(weth, amountCollateral);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralWithoutMinting() public {
        address owner = msg.sender;

        vm.startPrank(owner);
        ERC20Mock collateralToken = new ERC20Mock();
        collateralToken.mint(user, 20 ether);
        tokenAddresses.push(address(collateralToken));
        priceFeedAddresses.push(wethPriceFeed);
        DSCEngine dsce1 = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        vm.stopPrank();

        vm.startPrank(user);
        collateralToken.approve(address(dsce1), amountCollateral);
        dsce1.depositeCollateral(address(collateralToken), amountCollateral);

        uint256 result = dsce1.checkCollateral(address(collateralToken), user);

        assertEq(result, amountCollateral);
        vm.stopPrank();
    }

    function testCanDepositedCollateralAndGetAccountInfo() public {
        address owner = msg.sender;

        vm.startPrank(owner);
        ERC20Mock collateralToken = new ERC20Mock();
        collateralToken.mint(user, 20 ether);
        tokenAddresses.push(address(collateralToken));
        priceFeedAddresses.push(wethPriceFeed);
        DSCEngine dsce1 = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        vm.stopPrank();

        vm.startPrank(user);
        collateralToken.approve(address(dsce1), amountCollateral);
        dsce1.depositeCollateral(address(collateralToken), amountCollateral);

        uint256 result = dsce1.getAccountCollateral(user);
        uint256 expectedResult = 2_000 * amountCollateral;

        assertEq(result, expectedResult);
        vm.stopPrank();
    }

    ///////////////////////////////////////
    // depositCollateralAndMintDsc Tests //
    ///////////////////////////////////////

    function testRevertsIfMintedDscBreaksHealthFactor() public {
        (, int256 price,,,) = MockAggregatorV3(wethPriceFeed).latestRoundData();
        amountToMint = (amountCollateral * (uint256(price) * dsce.getAdditionFeedPrecision())) / dsce.getPrecision();
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);

        uint256 expectedHealthFactor =
            dsce.calculateHealthFactor(amountToMint, dsce.getValueInUsd(weth, amountCollateral));
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__ReachLiquidationThreshold.selector, expectedHealthFactor)
        );
        dsce.depositeCollateralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    modifier depositedCollateralAndMintedDsc() {
        (, int256 price,,,) = MockAggregatorV3(wethPriceFeed).latestRoundData();
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositeCollateralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        uint256 expectedHealthFactor =
            dsce.calculateHealthFactor(amountToMint, dsce.getValueInUsd(weth, amountCollateral));
        uint256 healthFactor = dsce.getHealthFactor(user);
        vm.stopPrank();
        console2.log('healthFactor', healthFactor);
        assertEq(expectedHealthFactor, healthFactor);
    }

    ///////////////////////////////////
    // mintDsc Tests //
    ///////////////////////////////////
    // This test needs it's own custom setups
    function testRevertsIfMintAmountIsZero() public {
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        dsce.mintDSC(0);
    }

    function testRevertsIfMintAmountBreaksHealthFactor() public depositedCollateral {
        (, int256 price,,,) = MockAggregatorV3(wethPriceFeed).latestRoundData();
        amountToMint = (amountCollateral * (uint256(price) * dsce.getAdditionFeedPrecision())) / dsce.getPrecision();
        vm.startPrank(user);

        uint256 expectedHealthFactor =
            dsce.calculateHealthFactor(amountToMint, dsce.getValueInUsd(weth, amountCollateral));

        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__ReachLiquidationThreshold.selector, expectedHealthFactor)
        );
        dsce.mintDSC(amountToMint);
        vm.stopPrank();
    }

    function testCanMintDsc() public depositedCollateral {
        vm.startPrank(user);
        dsce.mintDSC(amountToMint);
        vm.stopPrank();
    }

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
