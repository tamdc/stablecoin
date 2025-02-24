// SPDX-License-Identifier: MIT

// Layout of ccontract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of function
// constructor
// recieve function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view and pure functions

pragma solidity ^0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title DSCEngine
 * @author tam.dangc
 *
 * The system is designed to be as minimal as posible, and have the tokens maintain a 1 token == $1 at all time.
 * This is the stable coin with the priorities:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only wETH and wBTC.
 *
 * Our DSC system should always be "overcollateralized".
 * At no point, the value of all collateralized <= the $ backed value of all DSC
 *
 * @notice This contract is the core of Decentralize Stablecoin system. It handles all the logic for minting and
 * redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MarkerDAO DSS system.
 */
contract DSCEngine is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error DSCEngine__NeedMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TokenNotAllowed(address token);
    error DSCEngine__TransferFailed();
    error DSCEngine__ReachLiquidationThreshold(uint256 healthFactor);
    error DSCEngine__MintFailed();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    DecentralizedStableCoin private immutable i_dsc;

    uint256 private constant LIQUIDATION_THRESHOLD = 50; // The maximum your DSC you can mint is 50% your total collatral
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITION_FEED_PRECISION = 10e8;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; // If Position has health factor smaller than this value, it will me liquidated

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amount) private s_DSCMinted;

    address[] private s_collateralTokens;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__NeedMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0)) {
            revert DSCEngine__TokenNotAllowed(tokenAddress);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /*//////////////////////////////////////////////////////////////  
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function depositeCollateralAndMintDSC() external {}

    /**
     * @param tokenCollateralAddress: The ERC20 token address of your collateral you are depositing
     * @param amountCollateral: the amount of collateral you are depositing
     */
    function depositeCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDSC() external {}

    function redeemCollateral() external {}

    /**
     * @param amountDscToMint: The amount DSC you want to mint
     * You can only mint DSC if you have enough colleteral
     */
    function mintDSC(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        revertIfHealthFactorBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    /*//////////////////////////////////////////////////////////////
              PRIVATE AND INTERNAL VIEW AND PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getValueInUsd(address token, uint256 amount) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        return ((uint256(price) * ADDITION_FEED_PRECISION) * amount) / PRECISION;
    }

    function _getAccountInformation(address user)
        internal
        view
        returns (uint256 totalDscMinted, uint256 collateralInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralInUsd = getAccountCollateral(user);
    }

    function _getHealthFactor(address user) internal view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralInUSD) = _getAccountInformation(user);
        return calculateHealthFactor(totalDscMinted, collateralInUSD);
    }

    /**
     * @notice Calculates the health factor of a user's account
     * @param totalDscMinted The amount user wanna mint
     * @param collateralInUsd Collateral value in USD
     * @return healthFactor The health factor from these 2 params
     */
    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralInUsd)
        public
        pure
        returns (uint256 healthFactor)
    {
        // If no debt is minted, then the health factor should be "infinite", since the user has no risk of liquidation
        if (totalDscMinted == 0) return type(uint256).max;

        uint256 collateralAdjustedForThreshold = (collateralInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // The reason we multiply by PRECISION before dividing by totalDscMinted is to maintain precision
        // and avoid rounding errors when dealing with integer division in Solidity.
        // That's why the MIN_HEALTH_FACTOR we compare to is 1e18 but not 1.
        healthFactor = (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;

        return healthFactor;
    }

    /*//////////////////////////////////////////////////////////////
              PUBLIC AND EXTERNAL VIEW AND PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @param user: the user address we want to check the health factor
     */
    function revertIfHealthFactorBroken(address user) public view {
        uint256 healthFactor = _getHealthFactor(user);

        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__ReachLiquidationThreshold(healthFactor);
        }
    }

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralInUsd) public pure returns (uint256) {
        return _calculateHealthFactor(totalDscMinted, collateralInUsd);
    }

    function getAccountCollateral(address user) public view returns (uint256 totalCollateral) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[token][user];
            totalCollateral += _getValueInUsd(token, amount);
        }
    }
}
