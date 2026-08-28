// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @notice Mock ERC-20 token with configurable decimals for local testing and simulation (e.g. Mock USDC).
 * @dev Intended strictly for local development and test environments. Not for production use.
 */
contract MockERC20 is ERC20 {
    uint8 private immutable _customDecimals;

    error ZeroAddress();

    /**
     * @param name_ Token name (e.g. "USD Coin")
     * @param symbol_ Token symbol (e.g. "USDC")
     * @param decimals_ Token decimal precision (typically 6 for USDC)
     */
    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _customDecimals = decimals_;
    }

    /**
     * @notice Returns custom decimals set during deployment.
     */
    function decimals() public view virtual override returns (uint8) {
        return _customDecimals;
    }

    /**
     * @notice Mints tokens to a specified address for testing.
     * @param to Recipient address.
     * @param amount Amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external {
        if (to == address(0)) revert ZeroAddress();
        _mint(to, amount);
    }

    /**
     * @notice Burns tokens from a specified address for testing.
     * @param from Address to burn tokens from.
     * @param amount Amount of tokens to burn.
     */
    function burn(address from, uint256 amount) external {
        if (from == address(0)) revert ZeroAddress();
        _burn(from, amount);
    }
}
