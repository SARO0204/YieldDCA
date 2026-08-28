// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title IYieldVault
 * @notice Interface defining custom errors, events, and external API for Module 2: ERC-4626 Yield Vault / Capital Management.
 * @dev Extends the standard OpenZeppelin IERC4626 interface with controlled strategy withdrawals,
 *      operator management, and deterministic asset-backed mock yield simulation.
 */
interface IYieldVault is IERC4626 {
    // ------------------------------------------------------------------------
    // CUSTOM ERRORS
    // ------------------------------------------------------------------------

    error ZeroDepositAmount();
    error ZeroWithdrawAmount();
    error UnauthorizedOperator(address caller);
    error InsufficientUserShares(address user, uint256 requiredShares, uint256 availableShares);
    error ZeroAddress();
    error InvalidAPY(uint256 apyBps);
    error InsufficientVaultAssets(uint256 requested, uint256 available);

    // ------------------------------------------------------------------------
    // EVENTS
    // ------------------------------------------------------------------------

    event YieldSimulated(address indexed caller, uint256 yieldAmount, uint256 newTotalAssets);
    event SimulatedAPYUpdated(uint256 oldApy, uint256 newApy);
    event OperatorAuthorizationSet(address indexed operator, bool authorized);
    event StrategyWithdrawal(address indexed user, address indexed receiver, uint256 assets, uint256 sharesBurned);

    // ------------------------------------------------------------------------
    // CONTROLLED STRATEGY WITHDRAWAL
    // ------------------------------------------------------------------------

    /**
     * @notice Performs a controlled partial or full withdrawal of assets on behalf of a user's strategy.
     * @dev Callable only by authorized execution operators or vault owner. Burns corresponding user shares.
     * @param user The address of the strategy owner whose shares will be burned.
     * @param assets The exact amount of underlying assets to withdraw.
     * @param receiver The recipient of the withdrawn assets.
     * @return shares The exact number of shares burned from the user.
     */
    function withdrawForStrategy(address user, uint256 assets, address receiver) external returns (uint256 shares);

    // ------------------------------------------------------------------------
    // OPERATOR MANAGEMENT
    // ------------------------------------------------------------------------

    /**
     * @notice Authorizes or deauthorizes an execution operator (e.g. Future Execution Manager).
     * @dev Only callable by the vault owner.
     * @param operator Address of the operator.
     * @param authorized True to authorize, false to revoke.
     */
    function setAuthorizedOperator(address operator, bool authorized) external;

    /**
     * @notice Checks whether an address is an authorized execution operator.
     * @param operator Address to query.
     * @return True if operator is authorized.
     */
    function isAuthorizedOperator(address operator) external view returns (bool);

    // ------------------------------------------------------------------------
    // MOCK YIELD SIMULATION
    // ------------------------------------------------------------------------

    /**
     * @notice Injects real underlying tokens into the vault to deterministically simulate yield generation.
     * @dev Transfers `amount` of underlying asset from caller to the vault, increasing totalAssets without increasing shares.
     * @param amount The amount of underlying assets to deposit as simulated yield.
     */
    function simulateYield(uint256 amount) external;

    /**
     * @notice Updates the informational simulated APY parameter (in basis points).
     * @dev Only callable by owner. Bounded by MAX_APY_BPS. Does not mutate totalAssets.
     * @param apyBps Simulated annual percentage yield in basis points (e.g. 500 = 5.00%).
     */
    function setSimulatedAPY(uint256 apyBps) external;

    /**
     * @notice Returns the current informational simulated APY in basis points.
     * @return The configured simulated APY.
     */
    function getCurrentAPY() external view returns (uint256);

    // ------------------------------------------------------------------------
    // DECISION ENGINE & CONVENIENCE VIEWS
    // ------------------------------------------------------------------------

    /**
     * @notice Returns the underlying asset value represented by a user's vault share balance.
     * @param user Address of the vault shareholder.
     * @return Current underlying asset equivalent value.
     */
    function getUserAssets(address user) external view returns (uint256);

    /**
     * @notice Returns the vault share balance of a user.
     * @param user Address of the user.
     * @return Number of vault shares owned.
     */
    function getUserShares(address user) external view returns (uint256);

    /**
     * @notice Returns a composite view of core vault metrics for the future Decision Engine.
     * @return totalAssets Current total underlying assets held in vault.
     * @return totalShares Current total vault shares in circulation.
     * @return simulatedAPY Current configured simulated APY in basis points.
     */
    function getVaultState() external view returns (uint256 totalAssets, uint256 totalShares, uint256 simulatedAPY);
}
