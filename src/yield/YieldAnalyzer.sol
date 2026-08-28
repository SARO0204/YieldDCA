// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IYieldAnalyzer} from "../interfaces/IYieldAnalyzer.sol";
import {IYieldVault} from "../interfaces/IYieldVault.sol";
import {YieldDataTypes} from "./YieldDataTypes.sol";

/**
 * @title YieldAnalyzer
 * @notice Provides view-only normalization of yield projections based on the active YieldVault.
 * @dev Computations assume simple interest based on the simulated APY to provide deterministic projections
 *      for the Decision Engine. It depends exclusively on Module 2 (YieldVault).
 */
contract YieldAnalyzer is IYieldAnalyzer {
    error InvalidVault();

    IYieldVault public immutable vault;

    uint256 private constant BPS_DENOMINATOR = 10_000;
    uint256 private constant DAYS_7 = 7 days;
    uint256 private constant DAYS_30 = 30 days;
    uint256 private constant DAYS_365 = 365 days;

    /**
     * @dev Initializes the analyzer with a YieldVault provider.
     * @param _vault Address of the Module 2 YieldVault contract.
     */
    constructor(address _vault) {
        if (_vault == address(0)) revert InvalidVault();
        vault = IYieldVault(_vault);
    }

    /**
     * @inheritdoc IYieldAnalyzer
     */
    function getYieldStateForUser(address user) external view returns (YieldDataTypes.YieldState memory) {
        uint256 principal = vault.getUserAssets(user);
        return _computeState(principal);
    }

    /**
     * @inheritdoc IYieldAnalyzer
     */
    function getYieldStateForAmount(uint256 principalAmount) external view returns (YieldDataTypes.YieldState memory) {
        return _computeState(principalAmount);
    }

    /**
     * @notice Internal logic to calculate deterministic yield projections based on current APY.
     */
    function _computeState(uint256 principal) internal view returns (YieldDataTypes.YieldState memory) {
        // Fetch current APY from the vault
        uint256 currentAPY = vault.getCurrentAPY();

        // Projected Yield = (Principal * APY / 10000) * (Time / 365 days)
        uint256 yearlyYield = (principal * currentAPY) / BPS_DENOMINATOR;

        uint256 yield7D = (yearlyYield * DAYS_7) / DAYS_365;
        uint256 yield30D = (yearlyYield * DAYS_30) / DAYS_365;

        return YieldDataTypes.YieldState({
            currentAPY: currentAPY,
            principalAssets: principal,
            projectedYield7D: yield7D,
            projectedYield30D: yield30D,
            projectedYield365D: yearlyYield
        });
    }
}
