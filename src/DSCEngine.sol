// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

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

contract DSCEngine {
    function depositCollateralAndMintDSC() external{}

    function depoistCollateral() external{}

    function redeemCollateral() external{}

    function redeemCollateralForDSC() external{}

    function mintDSC() external{}

    function burnDSC() external{}

    function liquidate() external{}

    function getHealthFactor() external view{}
}