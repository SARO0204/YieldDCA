// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IDCAStrategy} from "../src/interfaces/IDCAStrategy.sol";
import {DCAStrategyLib} from "../src/libraries/DCAStrategyLib.sol";

contract DCAStrategyLibHarness {
    function validateStrategyParams(IDCAStrategy.StrategyParams memory params, uint256 currentTimestamp)
        external
        pure
        returns (uint256)
    {
        return DCAStrategyLib.validateStrategyParams(params, currentTimestamp);
    }

    function validateUpdateParams(
        uint256 targetAllocation,
        uint256 frequency,
        uint256 maxDelay,
        uint256 minExecutionAmount,
        uint256 maxExecutionAmount
    ) external pure {
        DCAStrategyLib.validateUpdateParams(
            targetAllocation, frequency, maxDelay, minExecutionAmount, maxExecutionAmount
        );
    }

    function validateExecutionAmount(
        uint256 amount,
        uint256 minExecutionAmount,
        uint256 maxExecutionAmount,
        uint256 targetAllocation
    ) external pure returns (bool) {
        return DCAStrategyLib.validateExecutionAmount(amount, minExecutionAmount, maxExecutionAmount, targetAllocation);
    }

    function isExecutionDue(uint256 nextExecutionTime, uint256 currentTimestamp) external pure returns (bool) {
        return DCAStrategyLib.isExecutionDue(nextExecutionTime, currentTimestamp);
    }

    function isExecutionWindowOpen(uint256 nextExecutionTime, uint256 maxDelay, uint256 currentTimestamp)
        external
        pure
        returns (bool)
    {
        return DCAStrategyLib.isExecutionWindowOpen(nextExecutionTime, maxDelay, currentTimestamp);
    }

    function isOverdue(uint256 nextExecutionTime, uint256 maxDelay, uint256 currentTimestamp)
        external
        pure
        returns (bool)
    {
        return DCAStrategyLib.isOverdue(nextExecutionTime, maxDelay, currentTimestamp);
    }

    function calculateRemainingDelay(uint256 nextExecutionTime, uint256 maxDelay, uint256 currentTimestamp)
        external
        pure
        returns (uint256)
    {
        return DCAStrategyLib.calculateRemainingDelay(nextExecutionTime, maxDelay, currentTimestamp);
    }
}

contract DCAStrategyLibTest is Test {
    DCAStrategyLibHarness internal harness;

    address internal constant TOKEN_A = address(0x1111);
    address internal constant TOKEN_B = address(0x2222);

    function setUp() public {
        harness = new DCAStrategyLibHarness();
    }

    function test_validateStrategyParams_success_defaultTimestamp() public view {
        uint256 currentTime = 1000;
        IDCAStrategy.StrategyParams memory params = IDCAStrategy.StrategyParams({
            inputToken: TOKEN_A,
            targetToken: TOKEN_B,
            targetAllocation: 10_000e18,
            frequency: 1 days,
            maxDelay: 2 hours,
            minExecutionAmount: 100e18,
            maxExecutionAmount: 1000e18,
            firstExecutionTime: 0
        });

        uint256 nextExecutionTime = harness.validateStrategyParams(params, currentTime);
        assertEq(nextExecutionTime, currentTime, "Should default to current timestamp when 0");
    }

    function test_validateStrategyParams_success_futureTimestamp() public view {
        uint256 currentTime = 1000;
        uint256 futureTime = 2000;
        IDCAStrategy.StrategyParams memory params = IDCAStrategy.StrategyParams({
            inputToken: TOKEN_A,
            targetToken: TOKEN_B,
            targetAllocation: 10_000e18,
            frequency: 1 days,
            maxDelay: 2 hours,
            minExecutionAmount: 100e18,
            maxExecutionAmount: 1000e18,
            firstExecutionTime: futureTime
        });

        uint256 nextExecutionTime = harness.validateStrategyParams(params, currentTime);
        assertEq(nextExecutionTime, futureTime, "Should use provided future execution time");
    }

    function test_validateStrategyParams_revert_zeroInputToken() public {
        IDCAStrategy.StrategyParams memory params = IDCAStrategy.StrategyParams({
            inputToken: address(0),
            targetToken: TOKEN_B,
            targetAllocation: 10_000e18,
            frequency: 1 days,
            maxDelay: 2 hours,
            minExecutionAmount: 100e18,
            maxExecutionAmount: 1000e18,
            firstExecutionTime: 0
        });

        vm.expectRevert(IDCAStrategy.ZeroAddressInputToken.selector);
        harness.validateStrategyParams(params, 1000);
    }

    function test_validateStrategyParams_revert_zeroTargetToken() public {
        IDCAStrategy.StrategyParams memory params = IDCAStrategy.StrategyParams({
            inputToken: TOKEN_A,
            targetToken: address(0),
            targetAllocation: 10_000e18,
            frequency: 1 days,
            maxDelay: 2 hours,
            minExecutionAmount: 100e18,
            maxExecutionAmount: 1000e18,
            firstExecutionTime: 0
        });

        vm.expectRevert(IDCAStrategy.ZeroAddressTargetToken.selector);
        harness.validateStrategyParams(params, 1000);
    }

    function test_validateStrategyParams_revert_identicalTokens() public {
        IDCAStrategy.StrategyParams memory params = IDCAStrategy.StrategyParams({
            inputToken: TOKEN_A,
            targetToken: TOKEN_A,
            targetAllocation: 10_000e18,
            frequency: 1 days,
            maxDelay: 2 hours,
            minExecutionAmount: 100e18,
            maxExecutionAmount: 1000e18,
            firstExecutionTime: 0
        });

        vm.expectRevert(abi.encodeWithSelector(IDCAStrategy.IdenticalTokens.selector, TOKEN_A));
        harness.validateStrategyParams(params, 1000);
    }

    function test_validateStrategyParams_revert_pastFirstExecutionTime() public {
        uint256 currentTime = 1000;
        uint256 pastTime = 999;
        IDCAStrategy.StrategyParams memory params = IDCAStrategy.StrategyParams({
            inputToken: TOKEN_A,
            targetToken: TOKEN_B,
            targetAllocation: 10_000e18,
            frequency: 1 days,
            maxDelay: 2 hours,
            minExecutionAmount: 100e18,
            maxExecutionAmount: 1000e18,
            firstExecutionTime: pastTime
        });

        vm.expectRevert(abi.encodeWithSelector(IDCAStrategy.InvalidFirstExecutionTime.selector, pastTime, currentTime));
        harness.validateStrategyParams(params, currentTime);
    }

    function test_validateUpdateParams_reverts() public {
        // Zero target allocation
        vm.expectRevert(IDCAStrategy.ZeroTargetAllocation.selector);
        harness.validateUpdateParams(0, 1 days, 2 hours, 100e18, 1000e18);

        // Zero frequency
        vm.expectRevert(IDCAStrategy.ZeroFrequency.selector);
        harness.validateUpdateParams(10_000e18, 0, 2 hours, 100e18, 1000e18);

        // Zero maxDelay
        vm.expectRevert(IDCAStrategy.ZeroMaxDelay.selector);
        harness.validateUpdateParams(10_000e18, 1 days, 0, 100e18, 1000e18);

        // Zero minExecutionAmount
        vm.expectRevert(IDCAStrategy.ZeroMinExecutionAmount.selector);
        harness.validateUpdateParams(10_000e18, 1 days, 2 hours, 0, 1000e18);

        // Zero maxExecutionAmount
        vm.expectRevert(IDCAStrategy.ZeroMaxExecutionAmount.selector);
        harness.validateUpdateParams(10_000e18, 1 days, 2 hours, 100e18, 0);

        // minExecutionAmount > maxExecutionAmount
        vm.expectRevert(abi.encodeWithSelector(IDCAStrategy.MinExecutionExceedsMax.selector, 1000e18, 500e18));
        harness.validateUpdateParams(10_000e18, 1 days, 2 hours, 1000e18, 500e18);

        // maxExecutionAmount > targetAllocation
        vm.expectRevert(
            abi.encodeWithSelector(IDCAStrategy.MaxExecutionExceedsAllocation.selector, 15_000e18, 10_000e18)
        );
        harness.validateUpdateParams(10_000e18, 1 days, 2 hours, 100e18, 15_000e18);

        // minExecutionAmount > targetAllocation
        vm.expectRevert(
            abi.encodeWithSelector(IDCAStrategy.MinExecutionExceedsAllocation.selector, 12_000e18, 10_000e18)
        );
        harness.validateUpdateParams(10_000e18, 1 days, 2 hours, 12_000e18, 12_000e18);
    }

    function test_validateExecutionAmount() public view {
        uint256 min = 100e18;
        uint256 max = 1000e18;
        uint256 alloc = 5000e18;

        // Valid amounts
        assertTrue(harness.validateExecutionAmount(100e18, min, max, alloc), "Min amount should be valid");
        assertTrue(harness.validateExecutionAmount(500e18, min, max, alloc), "Mid amount should be valid");
        assertTrue(harness.validateExecutionAmount(1000e18, min, max, alloc), "Max amount should be valid");

        // Invalid amounts
        assertFalse(harness.validateExecutionAmount(0, min, max, alloc), "Zero amount should be invalid");
        assertFalse(harness.validateExecutionAmount(99e18, min, max, alloc), "Below min should be invalid");
        assertFalse(harness.validateExecutionAmount(1001e18, min, max, alloc), "Above max should be invalid");
        assertFalse(harness.validateExecutionAmount(6000e18, min, 6000e18, alloc), "Above alloc should be invalid");
    }

    function test_timingCalculations() public view {
        uint256 nextTime = 1000;
        uint256 maxDelay = 200; // window: [1000, 1200]

        // 1. BEFORE DUE (t = 900)
        assertFalse(harness.isExecutionDue(nextTime, 900));
        assertFalse(harness.isExecutionWindowOpen(nextTime, maxDelay, 900));
        assertFalse(harness.isOverdue(nextTime, maxDelay, 900));
        assertEq(harness.calculateRemainingDelay(nextTime, maxDelay, 900), 200);

        // 2. EXACTLY DUE (t = 1000)
        assertTrue(harness.isExecutionDue(nextTime, 1000));
        assertTrue(harness.isExecutionWindowOpen(nextTime, maxDelay, 1000));
        assertFalse(harness.isOverdue(nextTime, maxDelay, 1000));
        assertEq(harness.calculateRemainingDelay(nextTime, maxDelay, 1000), 200);

        // 3. MID WINDOW (t = 1050)
        assertTrue(harness.isExecutionDue(nextTime, 1050));
        assertTrue(harness.isExecutionWindowOpen(nextTime, maxDelay, 1050));
        assertFalse(harness.isOverdue(nextTime, maxDelay, 1050));
        assertEq(harness.calculateRemainingDelay(nextTime, maxDelay, 1050), 150);

        // 4. AT DEADLINE BOUNDARY (t = 1200)
        assertTrue(harness.isExecutionDue(nextTime, 1200));
        assertTrue(harness.isExecutionWindowOpen(nextTime, maxDelay, 1200));
        assertFalse(harness.isOverdue(nextTime, maxDelay, 1200));
        assertEq(harness.calculateRemainingDelay(nextTime, maxDelay, 1200), 0);

        // 5. OVERDUE (t = 1201)
        assertTrue(harness.isExecutionDue(nextTime, 1201));
        assertFalse(harness.isExecutionWindowOpen(nextTime, maxDelay, 1201));
        assertTrue(harness.isOverdue(nextTime, maxDelay, 1201));
        assertEq(harness.calculateRemainingDelay(nextTime, maxDelay, 1201), 0);
    }
}
