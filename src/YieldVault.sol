// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IYieldVault} from "./interfaces/IYieldVault.sol";

/**
 * @title YieldVault
 * @notice Implementation of Module 2: ERC-4626 Yield Vault / Capital Management.
 * @dev Manages user capital custody, mints/burns ERC-4626 vault shares, provides deterministic
 *      asset-backed mock yield simulation, and supports controlled partial withdrawals for future DCA execution.
 *
 * Architectural Boundaries:
 * - Module 2 manages capital custody and share accounting.
 * - Module 2 NEVER stores DCA strategy parameters, performs swaps, checks price feeds, or executes market decisions.
 * - Yield is genuinely asset-backed: `simulateYield` transfers real underlying tokens into the vault.
 */
contract YieldVault is ERC4626, Ownable, IYieldVault {
    using SafeERC20 for IERC20;

    // ------------------------------------------------------------------------
    // CONSTANTS & STORAGE
    // ------------------------------------------------------------------------

    /// @notice Maximum allowed simulated APY in basis points (10,000 bps = 100.00%).
    uint256 public constant MAX_APY_BPS = 10_000;

    /// @notice Informational simulated annual percentage yield in basis points (e.g. 500 = 5.00%).
    uint256 private _simulatedAPY;

    /// @notice Mapping of authorized execution operators (e.g. Future Execution Manager).
    mapping(address => bool) private _authorizedOperators;

    // ------------------------------------------------------------------------
    // MODIFIERS
    // ------------------------------------------------------------------------

    /**
     * @dev Restricts access to the vault owner or authorized execution operators.
     */
    modifier onlyAuthorizedOperator() {
        if (msg.sender != owner() && !_authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }
        _;
    }

    // ------------------------------------------------------------------------
    // CONSTRUCTOR
    // ------------------------------------------------------------------------

    /**
     * @notice Initializes the ERC-4626 Yield Vault with an underlying asset and owner.
     * @param asset_ The underlying ERC-20 asset (e.g. Mock USDC).
     * @param name_ Name of the vault share token (e.g. "Yield DCA Vault Share").
     * @param symbol_ Symbol of the vault share token (e.g. "ydcaUSDC").
     * @param initialOwner Address of the administrative owner.
     */
    constructor(IERC20 asset_, string memory name_, string memory symbol_, address initialOwner)
        ERC4626(asset_)
        ERC20(name_, symbol_)
        Ownable(initialOwner)
    {
        if (address(asset_) == address(0)) revert ZeroAddress();
    }

    // ------------------------------------------------------------------------
    // CONTROLLED STRATEGY WITHDRAWAL
    // ------------------------------------------------------------------------

    /// @inheritdoc IYieldVault
    function withdrawForStrategy(address user, uint256 assets, address receiver)
        external
        onlyAuthorizedOperator
        returns (uint256 shares)
    {
        if (user == address(0) || receiver == address(0)) revert ZeroAddress();
        if (assets == 0) revert ZeroWithdrawAmount();

        uint256 currentTotalAssets = totalAssets();
        if (assets > currentTotalAssets) {
            revert InsufficientVaultAssets(assets, currentTotalAssets);
        }

        // Calculate required shares to burn using ERC-4626 ceiling rounding (rounds up against user)
        shares = previewWithdraw(assets);

        uint256 userShares = balanceOf(user);
        if (shares > userShares) {
            revert InsufficientUserShares(user, shares, userShares);
        }

        _burn(user, shares);
        IERC20(asset()).safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, user, assets, shares);
        emit StrategyWithdrawal(user, receiver, assets, shares);
    }

    // ------------------------------------------------------------------------
    // OPERATOR MANAGEMENT
    // ------------------------------------------------------------------------

    /// @inheritdoc IYieldVault
    function setAuthorizedOperator(address operator, bool authorized) external onlyOwner {
        if (operator == address(0)) revert ZeroAddress();
        _authorizedOperators[operator] = authorized;
        emit OperatorAuthorizationSet(operator, authorized);
    }

    /// @inheritdoc IYieldVault
    function isAuthorizedOperator(address operator) external view returns (bool) {
        return (operator == owner() || _authorizedOperators[operator]);
    }

    // ------------------------------------------------------------------------
    // MOCK YIELD SIMULATION
    // ------------------------------------------------------------------------

    /// @inheritdoc IYieldVault
    function simulateYield(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroDepositAmount();

        // Real asset-backed yield: transfer underlying tokens from caller to vault
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);

        emit YieldSimulated(msg.sender, amount, totalAssets());
    }

    /// @inheritdoc IYieldVault
    function setSimulatedAPY(uint256 apyBps) external onlyOwner {
        if (apyBps > MAX_APY_BPS) revert InvalidAPY(apyBps);

        uint256 oldApy = _simulatedAPY;
        _simulatedAPY = apyBps;

        emit SimulatedAPYUpdated(oldApy, apyBps);
    }

    /// @inheritdoc IYieldVault
    function getCurrentAPY() external view returns (uint256) {
        return _simulatedAPY;
    }

    // ------------------------------------------------------------------------
    // DECISION ENGINE & CONVENIENCE VIEWS
    // ------------------------------------------------------------------------

    /// @inheritdoc IYieldVault
    function getUserAssets(address user) external view returns (uint256) {
        return convertToAssets(balanceOf(user));
    }

    /// @inheritdoc IYieldVault
    function getUserShares(address user) external view returns (uint256) {
        return balanceOf(user);
    }

    /// @inheritdoc IYieldVault
    function getVaultState() external view returns (uint256 totalAssets_, uint256 totalShares_, uint256 simulatedAPY_) {
        return (totalAssets(), totalSupply(), _simulatedAPY);
    }
}
