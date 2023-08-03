// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Priyanshu Pandey
 * @notice The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg. This stablecoin has properties:
 * -Exogenous Collateral
 * -Dollar Pegged
 * -Algoritmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by WETH and WBTC.
 *
 * Our DSC system should be "overcollateralized". At no point, should the value of the collateral backing the DSC be less than the value of the DSC.
 *
 * @notice This contract is the core of the DSC System. It handles all the logic for mining and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is very loosely based on the MAKERDAO DSS (DAI) system.
 */

contract DSCEngine is ReentrancyGuard {

    //error
    error DSCEngine__NeedMoreThanZero();
    error DSCEngine__TokenAddressAndPriceFeedAddressLengthMismatch();
    error DSCEngine__TokenNotSupported();
    error DSCEngine__TransferFromFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();

    uint256 private constant s_ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    //mapping
    mapping(address token => address priceFeed) private s_priceFeeds;
    
    mapping(address user => mapping(address token => uint256 amount)) private s_userCollateralDeposited;

    mapping(address user => uint256 amountDscMinted) private s_userDscMinted;

    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    //Events
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    //Modifiers
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotSupported();
        }
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressAndPriceFeedAddressLengthMismatch();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    function depositCollateralAndMintDSC() external {}

    /**
     *
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_userCollateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if(!success){
            revert DSCEngine__TransferFromFailed();
        }
    }

    function redeemCollateral() external {}

    function redeemCollateralForDSC() external {}

    // 1. Check if the collater value > DSC amount.
    /**
     * 
     * @param amountDscToMint The amount of DSC to mint
     * @notice They must have more collateral than the minimum threshold.
     */
    function mintDSC(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        s_userDscMinted[msg.sender] += amountDscToMint;
        _revertIfHealFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if(!minted){
            revert DSCEngine__MintFailed();
        }
    }

    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    //Internal Functions

    function _getAccountInformation(address user) private view returns (uint256 totalDscMinted, uint256 collateralValueinUsd){
        totalDscMinted = s_userDscMinted[user];
        collateralValueinUsd = getAccountCollateralValueinUsd(user);
    }

    /** 
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they cant get liquidated.
    */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueinUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueinUsd * LIQUIDATION_THRESHOLD)/LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold*PRECISION)/totalDscMinted;
    }

    function _revertIfHealFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if(userHealthFactor < MIN_HEALTH_FACTOR){
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function getAccountCollateralValueinUsd(address user) public view returns(uint256 totalCollateralValueinUsd){
        for(uint256 i=0;i<s_collateralTokens.length; i++){
            address token = s_collateralTokens[i];
            uint256 amount = s_userCollateralDeposited[user][token];
            totalCollateralValueinUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueinUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();

        return ((uint256(price) * s_ADDITIONAL_FEED_PRECISION) *amount)/ PRECISION;
    }
}
