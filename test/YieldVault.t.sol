// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {YieldVault} from "../src/YieldVault.sol";
import {IYieldVault} from "../src/interfaces/IYieldVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract YieldVaultTest is Test {
    MockERC20 internal usdc;
    YieldVault internal vault;

    address internal owner = address(0x00A);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal operator = address(0x09E);
    address internal executionReceiver = address(0x8888);

    event YieldSimulated(address indexed caller, uint256 yieldAmount, uint256 newTotalAssets);
    event SimulatedAPYUpdated(uint256 oldApy, uint256 newApy);
    event OperatorAuthorizationSet(address indexed operator, bool authorized);
    event StrategyWithdrawal(address indexed user, address indexed receiver, uint256 assets, uint256 sharesBurned);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function setUp() public {
        vm.startPrank(owner);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        vault = new YieldVault(IERC20(address(usdc)), "Yield DCA Vault Share", "ydcaUSDC", owner);
        vm.stopPrank();

        // Mint initial USDC balances for tests
        usdc.mint(alice, 100_000e6);
        usdc.mint(bob, 100_000e6);
        usdc.mint(owner, 100_000e6);

        // Approve vault
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(owner);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ========================================================================
    // DEPLOYMENT & METADATA TESTS
    // ========================================================================

    function test_deployment_metadata() public view {
        assertEq(vault.asset(), address(usdc), "Underlying asset mismatch");
        assertEq(vault.name(), "Yield DCA Vault Share", "Name mismatch");
        assertEq(vault.symbol(), "ydcaUSDC", "Symbol mismatch");
        assertEq(vault.decimals(), 6, "Decimals mismatch");
        assertEq(vault.owner(), owner, "Owner mismatch");
        assertEq(vault.totalAssets(), 0, "Initial totalAssets should be 0");
        assertEq(vault.totalSupply(), 0, "Initial totalSupply should be 0");
        assertEq(vault.getCurrentAPY(), 0, "Initial APY should be 0");
    }

    function test_deployment_revert_zeroAddressAsset() public {
        vm.expectRevert(IYieldVault.ZeroAddress.selector);
        new YieldVault(IERC20(address(0)), "Yield DCA Vault Share", "ydcaUSDC", owner);
    }

    function test_mockERC20_mintAndBurn() public {
        MockERC20 token = new MockERC20("Test", "TST", 18);
        assertEq(token.decimals(), 18);

        token.mint(alice, 1000);
        assertEq(token.balanceOf(alice), 1000);

        token.burn(alice, 400);
        assertEq(token.balanceOf(alice), 600);
    }

    function test_mockERC20_reverts() public {
        MockERC20 token = new MockERC20("Test", "TST", 18);

        vm.expectRevert(MockERC20.ZeroAddress.selector);
        token.mint(address(0), 1000);

        vm.expectRevert(MockERC20.ZeroAddress.selector);
        token.burn(address(0), 1000);
    }

    // ========================================================================
    // STANDARD ERC-4626 DEPOSIT & MINT TESTS
    // ========================================================================

    function test_deposit_success() public {
        uint256 depositAmount = 10_000e6;

        vm.expectEmit(true, true, false, true);
        emit Deposit(alice, alice, depositAmount, depositAmount);

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        assertEq(shares, depositAmount, "Shares minted should equal deposit amount on 1:1");
        assertEq(vault.balanceOf(alice), depositAmount, "Alice share balance mismatch");
        assertEq(vault.totalAssets(), depositAmount, "Total assets mismatch");
        assertEq(vault.totalSupply(), depositAmount, "Total supply mismatch");
        assertEq(usdc.balanceOf(address(vault)), depositAmount, "Vault token balance mismatch");
        assertEq(vault.getUserAssets(alice), depositAmount, "getUserAssets mismatch");
        assertEq(vault.getUserShares(alice), depositAmount, "getUserShares mismatch");
    }

    function test_mint_success() public {
        uint256 sharesToMint = 5_000e6;

        vm.prank(alice);
        uint256 assetsConsumed = vault.mint(sharesToMint, alice);

        assertEq(assetsConsumed, sharesToMint, "Assets consumed mismatch");
        assertEq(vault.balanceOf(alice), sharesToMint, "Share balance mismatch");
        assertEq(vault.totalAssets(), sharesToMint, "Total assets mismatch");
    }

    function test_deposit_zeroAmount() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(0, alice);
        assertEq(shares, 0, "Zero deposit should yield zero shares");
    }

    // ========================================================================
    // STANDARD ERC-4626 WITHDRAW & REDEEM TESTS
    // ========================================================================

    function test_withdraw_success() public {
        uint256 depositAmount = 10_000e6;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 withdrawAmount = 4_000e6;
        uint256 aliceBalBefore = usdc.balanceOf(alice);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(alice, alice, alice, withdrawAmount, withdrawAmount);

        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(withdrawAmount, alice, alice);

        assertEq(sharesBurned, withdrawAmount, "Shares burned mismatch");
        assertEq(usdc.balanceOf(alice), aliceBalBefore + withdrawAmount, "Alice token balance mismatch");
        assertEq(vault.balanceOf(alice), depositAmount - withdrawAmount, "Alice shares mismatch");
        assertEq(vault.totalAssets(), depositAmount - withdrawAmount, "Remaining totalAssets mismatch");
    }

    function test_redeem_success() public {
        uint256 depositAmount = 10_000e6;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 redeemShares = 6_000e6;
        uint256 aliceBalBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        uint256 assetsReturned = vault.redeem(redeemShares, alice, alice);

        assertEq(assetsReturned, redeemShares, "Assets returned mismatch");
        assertEq(usdc.balanceOf(alice), aliceBalBefore + redeemShares, "Alice balance mismatch");
        assertEq(vault.balanceOf(alice), depositAmount - redeemShares, "Remaining shares mismatch");
    }

    // ========================================================================
    // PREVIEW & CONVERSION VIEWS TESTS
    // ========================================================================

    function test_previewAndConversionFunctions() public {
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        // Inject 1,000 USDC yield -> totalAssets = 11,000e6, totalSupply = 10,000e6 (1 share ≈ 1.10 USDC)
        vm.prank(owner);
        vault.simulateYield(1_000e6);

        // Verify conversion consistency
        uint256 expectedShares = vault.convertToShares(1_100e6);
        uint256 expectedAssets = vault.convertToAssets(1_000e6);

        assertApproxEqAbs(expectedShares, 1_000e6, 2, "Shares conversion approximation");
        assertApproxEqAbs(expectedAssets, 1_100e6, 2, "Assets conversion approximation");

        assertEq(vault.previewDeposit(1_100e6), vault.convertToShares(1_100e6));
        assertEq(vault.previewRedeem(1_000e6), vault.convertToAssets(1_000e6));

        assertEq(vault.maxDeposit(alice), type(uint256).max);
        assertEq(vault.maxMint(alice), type(uint256).max);
        assertEq(vault.maxWithdraw(alice), vault.convertToAssets(vault.balanceOf(alice)));
        assertEq(vault.maxRedeem(alice), 10_000e6);
    }

    // ========================================================================
    // DETERMINISTIC ASSET-BACKED MOCK YIELD TESTS
    // ========================================================================

    function test_simulateYield_success() public {
        uint256 depositAmount = 10_000e6;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 yieldAmount = 100e6;
        uint256 ownerBalBefore = usdc.balanceOf(owner);

        vm.expectEmit(true, false, false, true);
        emit YieldSimulated(owner, yieldAmount, depositAmount + yieldAmount);

        vm.prank(owner);
        vault.simulateYield(yieldAmount);

        // Real asset backing
        assertEq(vault.totalAssets(), depositAmount + yieldAmount, "totalAssets should increase by yield");
        assertEq(
            usdc.balanceOf(address(vault)), depositAmount + yieldAmount, "Vault token balance must equal totalAssets"
        );
        assertEq(vault.totalSupply(), depositAmount, "totalSupply should remain unchanged");
        assertEq(usdc.balanceOf(owner), ownerBalBefore - yieldAmount, "Yield tokens should be transferred from owner");

        // Alice share value increased from 10,000 to ~10,100 USDC
        assertApproxEqAbs(vault.getUserAssets(alice), depositAmount + yieldAmount, 2, "Alice asset value increased");
    }

    function test_simulateYield_revert_zeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(IYieldVault.ZeroDepositAmount.selector);
        vault.simulateYield(0);
    }

    function test_simulateYield_revert_nonOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vault.simulateYield(100e6);
    }

    // ========================================================================
    // SIMULATED APY TESTS
    // ========================================================================

    function test_setSimulatedAPY_success() public {
        assertEq(vault.getCurrentAPY(), 0);

        vm.expectEmit(false, false, false, true);
        emit SimulatedAPYUpdated(0, 500);

        vm.prank(owner);
        vault.setSimulatedAPY(500); // 5.00%

        assertEq(vault.getCurrentAPY(), 500);

        (uint256 assets, uint256 shares, uint256 apy) = vault.getVaultState();
        assertEq(assets, 0);
        assertEq(shares, 0);
        assertEq(apy, 500);

        // APY change must NEVER modify vault assets or share supply
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalSupply(), 0);
    }

    function test_setSimulatedAPY_revert_exceedsMax() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IYieldVault.InvalidAPY.selector, 10_001));
        vault.setSimulatedAPY(10_001); // Exceeds MAX_APY_BPS (100.00%)
    }

    function test_setSimulatedAPY_revert_nonOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vault.setSimulatedAPY(500);
    }

    // ========================================================================
    // OPERATOR AUTHORIZATION TESTS
    // ========================================================================

    function test_setAuthorizedOperator_success() public {
        assertFalse(vault.isAuthorizedOperator(operator));

        vm.expectEmit(true, false, false, true);
        emit OperatorAuthorizationSet(operator, true);

        vm.prank(owner);
        vault.setAuthorizedOperator(operator, true);

        assertTrue(vault.isAuthorizedOperator(operator));
        assertTrue(vault.isAuthorizedOperator(owner), "Owner should always be authorized");

        // Revoke
        vm.prank(owner);
        vault.setAuthorizedOperator(operator, false);
        assertFalse(vault.isAuthorizedOperator(operator));
    }

    function test_setAuthorizedOperator_revert_zeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(IYieldVault.ZeroAddress.selector);
        vault.setAuthorizedOperator(address(0), true);
    }

    function test_setAuthorizedOperator_revert_nonOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vault.setAuthorizedOperator(operator, true);
    }

    // ========================================================================
    // CONTROLLED STRATEGY PARTIAL WITHDRAWAL TESTS
    // ========================================================================

    function test_withdrawForStrategy_exactAccountingScenario() public {
        // 1. Alice deposits 10,000 USDC
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        // 2. Admin simulates 100 USDC yield
        vm.prank(owner);
        vault.simulateYield(100e6);

        // Vault state: 10,100 USDC assets, 10,000 shares
        assertEq(vault.totalAssets(), 10_100e6);
        assertEq(vault.totalSupply(), 10_000e6);

        // 3. Authorize execution operator
        vm.prank(owner);
        vault.setAuthorizedOperator(operator, true);

        // 4. Operator calls withdrawForStrategy for 6,000 USDC
        uint256 executionAmount = 6_000e6;
        uint256 expectedSharesBurned = vault.previewWithdraw(executionAmount);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(operator, executionReceiver, alice, executionAmount, expectedSharesBurned);

        vm.expectEmit(true, true, false, true);
        emit StrategyWithdrawal(alice, executionReceiver, executionAmount, expectedSharesBurned);

        vm.prank(operator);
        uint256 sharesBurned = vault.withdrawForStrategy(alice, executionAmount, executionReceiver);

        assertEq(sharesBurned, expectedSharesBurned, "Shares burned mismatch");
        assertEq(usdc.balanceOf(executionReceiver), executionAmount, "Receiver should receive exact 6000 USDC");

        // Remaining state:
        // Alice shares = 10000 - expectedSharesBurned
        // Vault assets = 10100 - 6000 = 4100 USDC
        assertEq(vault.balanceOf(alice), 10_000e6 - expectedSharesBurned, "Alice remaining shares mismatch");
        assertEq(vault.totalAssets(), 4_100e6, "Remaining vault assets should be 4100 USDC");
        assertEq(usdc.balanceOf(address(vault)), 4_100e6, "Vault token balance should be 4100 USDC");
        assertApproxEqAbs(vault.getUserAssets(alice), 4_100e6, 2, "Alice remaining asset value should be ~4100 USDC");
    }

    function test_withdrawForStrategy_ownerCanCall() public {
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        vm.prank(owner);
        uint256 sharesBurned = vault.withdrawForStrategy(alice, 2_000e6, executionReceiver);

        assertEq(sharesBurned, 2_000e6);
        assertEq(usdc.balanceOf(executionReceiver), 2_000e6);
    }

    function test_withdrawForStrategy_revert_unauthorizedCaller() public {
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IYieldVault.UnauthorizedOperator.selector, bob));
        vault.withdrawForStrategy(alice, 2_000e6, executionReceiver);
    }

    function test_withdrawForStrategy_revert_insufficientShares() public {
        // Alice deposits 1,000 USDC, Bob deposits 5,000 USDC (Vault totalAssets = 6,000)
        vm.prank(alice);
        vault.deposit(1_000e6, alice);

        vm.prank(bob);
        vault.deposit(5_000e6, bob);

        vm.prank(owner);
        vault.setAuthorizedOperator(operator, true);

        // Attempting to withdraw 2,000 USDC on behalf of Alice who only deposited 1,000 USDC
        uint256 expectedShares = vault.previewWithdraw(2_000e6);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(IYieldVault.InsufficientUserShares.selector, alice, expectedShares, 1_000e6)
        );
        vault.withdrawForStrategy(alice, 2_000e6, executionReceiver);
    }

    function test_withdrawForStrategy_revert_insufficientVaultAssets() public {
        vm.prank(alice);
        vault.deposit(1_000e6, alice);

        vm.prank(owner);
        vault.setAuthorizedOperator(operator, true);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IYieldVault.InsufficientVaultAssets.selector, 5_000e6, 1_000e6));
        vault.withdrawForStrategy(alice, 5_000e6, executionReceiver);
    }

    function test_withdrawForStrategy_revert_zeroAmount() public {
        vm.prank(owner);
        vault.setAuthorizedOperator(operator, true);

        vm.prank(operator);
        vm.expectRevert(IYieldVault.ZeroWithdrawAmount.selector);
        vault.withdrawForStrategy(alice, 0, executionReceiver);
    }

    function test_withdrawForStrategy_revert_zeroAddresses() public {
        vm.prank(owner);
        vault.setAuthorizedOperator(operator, true);

        vm.prank(operator);
        vm.expectRevert(IYieldVault.ZeroAddress.selector);
        vault.withdrawForStrategy(address(0), 1_000e6, executionReceiver);

        vm.prank(operator);
        vm.expectRevert(IYieldVault.ZeroAddress.selector);
        vault.withdrawForStrategy(alice, 1_000e6, address(0));
    }

    // ========================================================================
    // MULTI-USER PROPORTIONAL YIELD & PARTIAL WITHDRAWAL
    // ========================================================================

    function test_multiUser_proportionalYield() public {
        // Alice deposits 6,000 USDC (60%)
        vm.prank(alice);
        vault.deposit(6_000e6, alice);

        // Bob deposits 4,000 USDC (40%)
        vm.prank(bob);
        vault.deposit(4_000e6, bob);

        assertEq(vault.totalAssets(), 10_000e6);
        assertEq(vault.totalSupply(), 10_000e6);

        // Admin injects 1,000 USDC yield
        vm.prank(owner);
        vault.simulateYield(1_000e6);

        assertEq(vault.totalAssets(), 11_000e6);
        assertEq(vault.totalSupply(), 10_000e6);

        // Proportional asset distribution:
        // Alice: 6,000 shares * 1.10 = ~6,600 USDC
        // Bob: 4,000 shares * 1.10 = ~4,400 USDC
        assertApproxEqAbs(vault.getUserAssets(alice), 6_600e6, 2, "Alice should own ~6600 USDC");
        assertApproxEqAbs(vault.getUserAssets(bob), 4_400e6, 2, "Bob should own ~4400 USDC");

        // Alice performs partial withdrawal of 3,300 USDC
        vm.prank(owner);
        vault.setAuthorizedOperator(operator, true);

        vm.prank(operator);
        vault.withdrawForStrategy(alice, 3_300e6, executionReceiver);

        // Bob's value must remain completely untouched at ~4,400 USDC
        assertApproxEqAbs(vault.getUserAssets(bob), 4_400e6, 2, "Bob asset value should remain ~4400 USDC");
        assertEq(vault.balanceOf(bob), 4_000e6, "Bob share count should remain 4000");

        // Alice remaining value: ~3,300 USDC
        assertApproxEqAbs(vault.getUserAssets(alice), 3_300e6, 2, "Alice remaining value should be ~3300 USDC");
        assertEq(vault.totalAssets(), 7_700e6, "Vault remaining total assets should be 7700 USDC");
    }

    // ========================================================================
    // FUZZ & INVARIANT TESTS
    // ========================================================================

    function testFuzz_depositAndWithdraw(uint256 depositAmount, uint256 withdrawPercent) public {
        depositAmount = bound(depositAmount, 100e6, 1_000_000e6);
        withdrawPercent = bound(withdrawPercent, 1, 100);

        usdc.mint(alice, depositAmount);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Invariant: totalAssets == vault balance
        assertEq(vault.totalAssets(), usdc.balanceOf(address(vault)));
        assertEq(vault.totalAssets(), depositAmount);

        uint256 withdrawAmount = (depositAmount * withdrawPercent) / 100;
        if (withdrawAmount > 0) {
            vm.prank(alice);
            vault.withdraw(withdrawAmount, alice, alice);

            // Invariant maintained after withdrawal
            assertEq(vault.totalAssets(), usdc.balanceOf(address(vault)));
            assertEq(vault.totalAssets(), depositAmount - withdrawAmount);
        }
    }

    function testFuzz_yieldSimulationInvariants(uint256 depositAmount, uint256 yieldAmount) public {
        depositAmount = bound(depositAmount, 1_000e6, 1_000_000e6);
        yieldAmount = bound(yieldAmount, 1e6, 100_000e6);

        usdc.mint(alice, depositAmount);
        usdc.mint(owner, yieldAmount);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 supplyBefore = vault.totalSupply();

        vm.prank(owner);
        vault.simulateYield(yieldAmount);

        // Invariant: Total supply is unchanged by yield
        assertEq(vault.totalSupply(), supplyBefore, "Yield must never alter total share supply");

        // Invariant: Total assets equals token balance exactly
        assertEq(vault.totalAssets(), usdc.balanceOf(address(vault)));
        assertEq(vault.totalAssets(), depositAmount + yieldAmount);

        // Invariant: Share price increases
        assertTrue(vault.convertToAssets(1e6) >= 1e6, "Share price must be >= 1:1 after non-negative yield");
    }
}
