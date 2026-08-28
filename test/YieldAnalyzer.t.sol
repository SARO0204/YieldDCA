// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {YieldAnalyzer} from "../src/yield/YieldAnalyzer.sol";
import {YieldVault} from "../src/YieldVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {YieldDataTypes} from "../src/yield/YieldDataTypes.sol";

contract YieldAnalyzerTest is Test {
    YieldAnalyzer public analyzer;
    YieldVault public vault;
    MockERC20 public mockToken;

    address public user = address(0x123);
    uint256 public constant INITIAL_DEPOSIT = 10_000e6; // 10,000 USDC

    function setUp() public {
        mockToken = new MockERC20("Mock USDC", "USDC", 6);
        vault = new YieldVault(mockToken, "Vault", "vUSDC", address(this));
        analyzer = new YieldAnalyzer(address(vault));

        // Setup user funds
        mockToken.mint(user, INITIAL_DEPOSIT);
        vm.startPrank(user);
        mockToken.approve(address(vault), INITIAL_DEPOSIT);
        vault.deposit(INITIAL_DEPOSIT, user);
        vm.stopPrank();
    }

    function test_RevertInvalidVault() public {
        vm.expectRevert(YieldAnalyzer.InvalidVault.selector);
        new YieldAnalyzer(address(0));
    }

    function test_GetYieldStateForAmount() public {
        // Set APY to 500 bps (5%)
        vault.setSimulatedAPY(500);

        uint256 amount = 1_000e6; // 1,000 USDC
        YieldDataTypes.YieldState memory state = analyzer.getYieldStateForAmount(amount);

        assertEq(state.currentAPY, 500);
        assertEq(state.principalAssets, 1_000e6);

        // 1,000 * 5% = 50 USDC per year
        assertEq(state.projectedYield365D, 50e6);

        // 7 days: (50e6 * 7) / 365 = 958904
        assertEq(state.projectedYield7D, (uint256(50e6) * 7 days) / 365 days);

        // 30 days: (50e6 * 30) / 365 = 4109589
        assertEq(state.projectedYield30D, (uint256(50e6) * 30 days) / 365 days);
    }

    function test_GetYieldStateForUser() public {
        // Set APY to 1000 bps (10%)
        vault.setSimulatedAPY(1000);

        // User deposited 10,000 USDC
        YieldDataTypes.YieldState memory state = analyzer.getYieldStateForUser(user);

        assertEq(state.currentAPY, 1000);
        assertEq(state.principalAssets, 10_000e6);

        // 10,000 * 10% = 1,000 USDC per year
        assertEq(state.projectedYield365D, 1_000e6);

        assertEq(state.projectedYield7D, (uint256(1_000e6) * 7 days) / 365 days);
        assertEq(state.projectedYield30D, (uint256(1_000e6) * 30 days) / 365 days);
    }
}
