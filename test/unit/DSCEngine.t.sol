// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Test, console2} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockAggregatorV3} from "test/mocks/MockAggregatorV3.sol";

contract TestDSCEngine is Test {
    event CollateralRedeemed(
        address indexed redeemFrom, address indexed redeemTo, address indexed token, uint256 amount
    );

    DecentralizedStableCoin public dsc;
    DSCEngine public dsce;
    DeployDSC public deployer;
    HelperConfig public config;

    address public weth;
    address public wbtc;
    address public wethPriceFeed;
    address public wbtcPriceFeed;

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;
    address public user = makeAddr("user");
    address liquidator = makeAddr("liquidator");

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
        ERC20Mock(wbtc).mint(liquidator, STARTING_ERC20_BALANCE);
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
        dsce1.depositCollateral(address(collateralToken), amountCollateral);
        vm.stopPrank();
    }

    function testRevertsIfCollateralZero() public {
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
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
        dsce1.depositCollateral(address(collateralContract), 1 ether);
        vm.stopBroadcast();
    }

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateral(weth, amountCollateral);
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
        dsce1.depositCollateral(address(collateralToken), amountCollateral);

        uint256 result = dsce1.getCollateralAmount(address(collateralToken), user);

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
        dsce1.depositCollateral(address(collateralToken), amountCollateral);

        uint256 result = dsce1.getAccountCollateral(user);
        uint256 expectedResult = 2_000 * amountCollateral;

        assertEq(result, expectedResult);
        vm.stopPrank();
    }

    function testRevertsIfTransferFromReverts() public {
        // Deploy a mock ERC20 that reverts on transferFrom
        address owner = msg.sender;
        vm.startPrank(owner);
        ERC20Mock collateralToken = new ERC20Mock();
        collateralToken.mint(user, 20 ether);
        tokenAddresses.push(address(collateralToken));
        priceFeedAddresses.push(wethPriceFeed);
        DSCEngine dsce1 = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        vm.stopPrank();

        // Mock a revert on transferFrom
        vm.startPrank(user);
        collateralToken.approve(address(dsce1), amountCollateral);
        vm.mockCall(
            address(collateralToken),
            abi.encodeWithSelector(IERC20.transferFrom.selector, user, address(dsce1), amountCollateral),
            abi.encode(false)
        );
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        dsce1.depositCollateral(address(collateralToken), amountCollateral);
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
        dsce.depositCollateralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    modifier depositedCollateralAndMintedDsc() {
        (, int256 price,,,) = MockAggregatorV3(wethPriceFeed).latestRoundData();
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, amountToMint);
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

    function testRevertsIfMintFails() public depositedCollateral {
        // Mock the mint function to return false
        vm.mockCall(
            address(dsc),
            abi.encodeWithSelector(DecentralizedStableCoin.mint.selector, user, amountToMint),
            abi.encode(false)
        );
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        dsce.mintDSC(amountToMint);
        vm.stopPrank();
    }

    ///////////////////////////////////
    // burnDsc Tests //
    ///////////////////////////////////

    function testRevertsIfBurnAmountIsZero() public {
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        dsce.burnDSC(0);
    }

    function testCantBurnMoreThanUserHas() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        uint256 amountExceeds = amountToMint + 1 ether;
        vm.expectRevert(DSCEngine.DSCEngine__AmountExceeds.selector);
        dsce.burnDSC(amountExceeds);
        vm.stopPrank();
    }

    function testCanBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        uint256 amountBeforeBurn = dsc.balanceOf(user);
        dsc.approve(address(dsce), amountToMint);
        dsce.burnDSC(amountToMint);
        uint256 amountAfterBurn = dsc.balanceOf(user);
        vm.assertEq(amountAfterBurn, amountBeforeBurn - amountToMint);
        vm.stopPrank();
    }

    function testRevertsIfBurnExceedsMinted() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        dsc.approve(address(dsce), amountToMint + 1 ether);
        vm.expectRevert(DSCEngine.DSCEngine__AmountExceeds.selector);
        dsce.burnDSC(amountToMint + 1 ether);
        vm.stopPrank();
    }

    ///////////////////////////////////
    // redeemCollateral Tests //
    //////////////////////////////////

    // this test needs it's own setup
    function testRevertsIfRedeemAmountIsZero() public depositedCollateral {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        dsce.redeemCollateral(address(weth), 0);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositedCollateral {
        vm.startPrank(user);
        uint256 amountBeforeRedeem = dsce.getCollateralAmount(weth, user); // 10 ether
        dsce.redeemCollateral(address(weth), amountCollateral);
        uint256 amountAfterRedeem = dsce.getCollateralAmount(weth, user); // 0 ether
        assertEq(amountAfterRedeem, amountBeforeRedeem - amountCollateral);
        vm.stopPrank();
    }

    function testEmitCollateralRedeemedWithCorrectArgs() public depositedCollateral {
        vm.expectEmit(true, true, true, true, address(dsce));
        emit CollateralRedeemed(address(user), address(user), weth, amountCollateral);

        vm.startPrank(user);
        dsce.redeemCollateral(weth, amountCollateral);
        vm.stopPrank();
    }

    function testRevertsIfRedeemExceedsCollateral() public depositedCollateral {
        vm.startPrank(user);
        uint256 excessiveAmount = amountCollateral + 1 ether;
        vm.expectRevert(DSCEngine.DSCEngine__AmountExceeds.selector);
        dsce.redeemCollateral(weth, excessiveAmount);
        vm.stopPrank();
    }

    function testRevertsIfRedeemTransferFails() public depositedCollateral {
        // Mock the transfer function to return false
        vm.mockCall(
            address(weth), abi.encodeWithSelector(IERC20.transfer.selector, user, amountCollateral), abi.encode(false)
        );
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        dsce.redeemCollateral(weth, amountCollateral);
        vm.stopPrank();
    }
    ///////////////////////////////////
    // redeemCollateralForDsc Tests //
    //////////////////////////////////

    function testMustRedeemMoreThanZero() public {
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        dsce.redeemCollateralForDSC(weth, amountCollateral, 0);
    }

    function testCanRedeemDepositedCollateral() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        dsc.approve(address(dsce), amountToMint);
        dsce.redeemCollateralForDSC(weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    ////////////////////////
    // healthFactor Tests //
    ////////////////////////

    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc {
        uint256 expectedHealthFactor = 100 ether;
        uint256 heathFactor = dsce.getHealthFactor(user);
        assertEq(expectedHealthFactor, heathFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDsc {
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        // Remember, we need $200 at all times if we have $100 of debt

        MockAggregatorV3(wethPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 userHealthFactor = dsce.getHealthFactor(user);
        // 180*50 (LIQUIDATION_THRESHOLD) / 100 (LIQUIDATION_PRECISION) / 100 (PRECISION) = 90 / 100 (totalDscMinted) =
        // 0.9
        assert(userHealthFactor == 0.9 ether);
    }

    ///////////////////////
    // Liquidation Tests //
    ///////////////////////

    // This test needs it's own setup
    function testMustImproveHealthFactorOnLiquidation() public {
        // Arrange - user
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        // Arrange - liquidator
        vm.startPrank(liquidator);
        ERC20Mock(wbtc).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDSC(wbtc, amountCollateral, amountToMint);

        vm.stopPrank();

        // Action
        MockAggregatorV3(wethPriceFeed).updateAnswer(18e8);
        uint256 hfBeforeLiquidated = dsce.getHealthFactor(user);

        vm.startPrank(liquidator);
        uint256 amountDscToCover = 10 ether;
        dsc.approve(address(dsce), amountDscToCover);
        dsce.liquidate(weth, user, amountDscToCover);
        uint256 hfAfterLiquidated = dsce.getHealthFactor(user);
        vm.stopPrank();

        assert(hfAfterLiquidated > hfBeforeLiquidated);
    }

    function testCantLiquidateGoodHealthFactor() public {
        // Arrange - user
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        // Arrange - liquidator
        vm.startPrank(liquidator);
        ERC20Mock(wbtc).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDSC(wbtc, amountCollateral, amountToMint);

        uint256 amountDscToCover = 10 ether;
        dsc.approve(address(dsce), amountDscToCover);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth, user, amountDscToCover);
        vm.stopPrank();
    }

    modifier liquidated() {
        // Arrange - user
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        uint256 userAmount = dsce.getAccountCollateral(user);

        // Arrange
        MockAggregatorV3(wethPriceFeed).updateAnswer(18e8);

        vm.startPrank(liquidator);
        ERC20Mock(wbtc).approve(address(dsce), 2 ether);
        dsce.depositCollateralAndMintDSC(wbtc, 2 ether, amountToMint);
        uint256 amountWalletLiquidator = ERC20Mock(weth).balanceOf(liquidator);
        dsc.approve(address(dsce), amountToMint);
        dsce.liquidate(weth, user, amountToMint);
        vm.stopPrank();

        _;
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 userCollateralBalanceLeft = dsce.getAccountCollateral(user);
        uint256 ethAmountOfLiquidator = ERC20Mock(weth).balanceOf(liquidator);

        uint256 totalBalanceCollateral = dsce.getValueInUsd(weth, amountCollateral);
        uint256 ethBalanceOfLiquidator = dsce.getValueInUsd(weth, ethAmountOfLiquidator);

        assertEq(totalBalanceCollateral, ethBalanceOfLiquidator + userCollateralBalanceLeft);
    }

    function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        uint256 userCollateralBalanceLeft = dsce.getAccountCollateral(user);

        assert(userCollateralBalanceLeft > 0);
    }

    function testLiquidatorDebtUnchangedAfterLiquidation() public liquidated {
        (uint256 dscMinted,) = dsce.getAccountInformation(liquidator);
        assertEq(dscMinted, amountToMint);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 dscMinted,) = dsce.getAccountInformation(user);
        assertEq(dscMinted, 0);
    }

    function testRevertsLiquidateWithHealthFactorAboveThreshold() public {
        // Arrange - user deposits and mints
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDSC(weth, amountCollateral, amountToMint / 2); // Mint less to keep health factor high
        vm.stopPrank();

        // Arrange - liquidator
        vm.startPrank(liquidator);
        ERC20Mock(wbtc).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDSC(wbtc, amountCollateral, amountToMint);
        dsc.approve(address(dsce), 10 ether);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth, user, 10 ether);
        vm.stopPrank();
    }

    function testRevertsLiquidateWithHighHealthFactor() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateral(weth, amountCollateral); // No DSC minted
        vm.stopPrank();
        vm.startPrank(liquidator);
        ERC20Mock(wbtc).approve(address(dsce), amountCollateral);
        dsce.depositCollateral(wbtc, amountCollateral);
        dsc.approve(address(dsce), 10 ether);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth, user, 10 ether);
        vm.stopPrank();
    }

    ///////////////////////////////////
    // View & Pure Function Tests //
    //////////////////////////////////
    function testGetCollateralTokenPriceFeed() public view {
        address priceFeed = dsce.getCollateralTokenPriceFeed(weth);
        assert(priceFeed == wethPriceFeed);
    }

    function testGetCollateralTokens() public view {
        address[] memory tokens = dsce.getCollateralTokens();
        assert(address(tokens[0]) == weth);
    }

    function testGetMinHealthFactor() public view {
        uint256 minHealthFactor = dsce.getMinHealthFactor();
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
    }

    function testGetLiquidationThreshold() public view {
        uint256 liquidationThreshold = dsce.getLiquidationThreshold();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    function testGetAccountCollateralValueFromInformation() public depositedCollateral {
        (, uint256 collateralValue) = dsce.getAccountInformation(user);
        uint256 expectedCollateralValue = dsce.getValueInUsd(weth, amountCollateral);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetCollateralBalanceOfUser() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        uint256 collateralBalance = dsce.getCollateralAmount(weth, user);
        assertEq(collateralBalance, amountCollateral);
    }

    function testGetAccountCollateralValue() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        uint256 collateralValue = dsce.getAccountCollateral(user);
        uint256 expectedCollateralValue = dsce.getValueInUsd(weth, amountCollateral);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetDsc() public view {
        address dscAddress = dsce.getDsc();
        assertEq(dscAddress, address(dsc));
    }

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

    function testCalculateHealthFactorWithZeroDscMinted() public depositedCollateral {
        uint256 collateralValue = dsce.getValueInUsd(weth, amountCollateral);
        uint256 healthFactor = dsce.calculateHealthFactor(0, collateralValue);
        assertEq(healthFactor, type(uint256).max);
    }

    function testRevertIfHealthFactorBroken() public depositedCollateralAndMintedDsc {
        // Lower WETH price to $18 to break health factor
        MockAggregatorV3(wethPriceFeed).updateAnswer(18e8); // 1 ETH = $18
        uint256 expectedHealthFactor = 0.9 ether; // 9e17, as calculated in testHealthFactorCanGoBelowOne
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__ReachLiquidationThreshold.selector, expectedHealthFactor)
        );
        dsce.revertIfHealthFactorBroken(user);
    }
}
