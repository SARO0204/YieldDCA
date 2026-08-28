// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {DCAEngine} from "../src/DCAEngine.sol";
import {IDCAStrategy} from "../src/interfaces/IDCAStrategy.sol";

contract DCAEngineTest is Test {
    DCAEngine internal engine;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal tokenA = address(0x1111);
    address internal tokenB = address(0x2222);

    event StrategyCreated(
        uint256 indexed strategyId,
        address indexed owner,
        address indexed inputToken,
        address targetToken,
        uint256 targetAllocation,
        uint256 frequency,
        uint256 maxDelay,
        uint256 minExecutionAmount,
        uint256 maxExecutionAmount,
        uint256 firstExecutionTime
    );

    event StrategyUpdated(
        uint256 indexed strategyId,
        address indexed owner,
        uint256 targetAllocation,
        uint256 frequency,
        uint256 maxDelay,
        uint256 minExecutionAmount,
        uint256 maxExecutionAmount
    );

    event StrategyPaused(uint256 indexed strategyId, address indexed owner);
    event StrategyResumed(uint256 indexed strategyId, address indexed owner);
    event StrategyCancelled(uint256 indexed strategyId, address indexed owner);

    function setUp() public {
        vm.warp(1_000_000); // set predictable timestamp
        engine = new DCAEngine();
    }

    function _defaultParams() internal view returns (IDCAStrategy.StrategyParams memory) {
        return IDCAStrategy.StrategyParams({
            inputToken: tokenA,
            targetToken: tokenB,
            targetAllocation: 10_000e18,
            frequency: 1 days,
            maxDelay: 4 hours,
            minExecutionAmount: 100e18,
            maxExecutionAmount: 1000e18,
            firstExecutionTime: 0
        });
    }

    // ========================================================================
    // CREATION & INITIALIZATION TESTS
    // ========================================================================

    function test_createStrategy_success_defaults() public {
        IDCAStrategy.StrategyParams memory params = _defaultParams();

        vm.expectEmit(true, true, true, true);
        emit StrategyCreated(1, alice, tokenA, tokenB, 10_000e18, 1 days, 4 hours, 100e18, 1000e18, block.timestamp);

        vm.prank(alice);
        uint256 id = engine.createStrategy(params);

        assertEq(id, 1, "Strategy ID should be 1");
        assertEq(engine.getStrategyCount(), 1, "Strategy count should be 1");

        IDCAStrategy.Strategy memory strategy = engine.getStrategy(id);
        assertEq(strategy.owner, alice, "Owner mismatch");
        assertEq(strategy.inputToken, tokenA, "InputToken mismatch");
        assertEq(strategy.targetToken, tokenB, "TargetToken mismatch");
        assertEq(strategy.targetAllocation, 10_000e18, "TargetAllocation mismatch");
        assertEq(strategy.frequency, 1 days, "Frequency mismatch");
        assertEq(strategy.maxDelay, 4 hours, "MaxDelay mismatch");
        assertEq(strategy.minExecutionAmount, 100e18, "MinExecutionAmount mismatch");
        assertEq(strategy.maxExecutionAmount, 1000e18, "MaxExecutionAmount mismatch");
        assertEq(strategy.nextExecutionTime, block.timestamp, "NextExecutionTime should default to block.timestamp");
        assertTrue(strategy.status == IDCAStrategy.StrategyStatus.ACTIVE, "Status should be ACTIVE");

        uint256[] memory aliceStrategies = engine.getUserStrategies(alice);
        assertEq(aliceStrategies.length, 1, "Alice should have 1 strategy");
        assertEq(aliceStrategies[0], 1, "Alice strategy ID mismatch");
    }

    function test_createStrategy_success_futureFirstExecutionTime() public {
        uint256 futureTime = block.timestamp + 3 days;
        IDCAStrategy.StrategyParams memory params = _defaultParams();
        params.firstExecutionTime = futureTime;

        vm.prank(alice);
        uint256 id = engine.createStrategy(params);

        IDCAStrategy.Strategy memory strategy = engine.getStrategy(id);
        assertEq(strategy.nextExecutionTime, futureTime, "NextExecutionTime should match future time");
    }

    function test_createStrategy_monotonicIdAssignment() public {
        IDCAStrategy.StrategyParams memory params = _defaultParams();

        vm.prank(alice);
        uint256 id1 = engine.createStrategy(params);
        vm.prank(bob);
        uint256 id2 = engine.createStrategy(params);
        vm.prank(alice);
        uint256 id3 = engine.createStrategy(params);

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(id3, 3);
        assertEq(engine.getStrategyCount(), 3);

        uint256[] memory aliceList = engine.getUserStrategies(alice);
        assertEq(aliceList.length, 2);
        assertEq(aliceList[0], 1);
        assertEq(aliceList[1], 3);

        uint256[] memory bobList = engine.getUserStrategies(bob);
        assertEq(bobList.length, 1);
        assertEq(bobList[0], 2);
    }

    // ========================================================================
    // CREATION VALIDATION & CUSTOM ERRORS
    // ========================================================================

    function test_createStrategy_revert_zeroInputToken() public {
        IDCAStrategy.StrategyParams memory params = _defaultParams();
        params.inputToken = address(0);

        vm.expectRevert(IDCAStrategy.ZeroAddressInputToken.selector);
        engine.createStrategy(params);
    }

    function test_createStrategy_revert_zeroTargetToken() public {
        IDCAStrategy.StrategyParams memory params = _defaultParams();
        params.targetToken = address(0);

        vm.expectRevert(IDCAStrategy.ZeroAddressTargetToken.selector);
        engine.createStrategy(params);
    }

    function test_createStrategy_revert_identicalTokens() public {
        IDCAStrategy.StrategyParams memory params = _defaultParams();
        params.targetToken = params.inputToken;

        vm.expectRevert(abi.encodeWithSelector(IDCAStrategy.IdenticalTokens.selector, params.inputToken));
        engine.createStrategy(params);
    }

    function test_createStrategy_revert_zeroTargetAllocation() public {
        IDCAStrategy.StrategyParams memory params = _defaultParams();
        params.targetAllocation = 0;

        vm.expectRevert(IDCAStrategy.ZeroTargetAllocation.selector);
        engine.createStrategy(params);
    }

    function test_createStrategy_revert_zeroFrequency() public {
        IDCAStrategy.StrategyParams memory params = _defaultParams();
        params.frequency = 0;

        vm.expectRevert(IDCAStrategy.ZeroFrequency.selector);
        engine.createStrategy(params);
    }

    function test_createStrategy_revert_zeroMaxDelay() public {
        IDCAStrategy.StrategyParams memory params = _defaultParams();
        params.maxDelay = 0;

        vm.expectRevert(IDCAStrategy.ZeroMaxDelay.selector);
        engine.createStrategy(params);
    }

    function test_createStrategy_revert_zeroMinExecutionAmount() public {
        IDCAStrategy.StrategyParams memory params = _defaultParams();
        params.minExecutionAmount = 0;

        vm.expectRevert(IDCAStrategy.ZeroMinExecutionAmount.selector);
        engine.createStrategy(params);
    }

    function test_createStrategy_revert_zeroMaxExecutionAmount() public {
        IDCAStrategy.StrategyParams memory params = _defaultParams();
        params.maxExecutionAmount = 0;

        vm.expectRevert(IDCAStrategy.ZeroMaxExecutionAmount.selector);
        engine.createStrategy(params);
    }

    function test_createStrategy_revert_minExceedsMax() public {
        IDCAStrategy.StrategyParams memory params = _defaultParams();
        params.minExecutionAmount = 500e18;
        params.maxExecutionAmount = 200e18;

        vm.expectRevert(abi.encodeWithSelector(IDCAStrategy.MinExecutionExceedsMax.selector, 500e18, 200e18));
        engine.createStrategy(params);
    }

    function test_createStrategy_revert_maxExceedsAllocation() public {
        IDCAStrategy.StrategyParams memory params = _defaultParams();
        params.targetAllocation = 1000e18;
        params.maxExecutionAmount = 2000e18;

        vm.expectRevert(abi.encodeWithSelector(IDCAStrategy.MaxExecutionExceedsAllocation.selector, 2000e18, 1000e18));
        engine.createStrategy(params);
    }

    function test_createStrategy_revert_pastFirstExecutionTime() public {
        IDCAStrategy.StrategyParams memory params = _defaultParams();
        params.firstExecutionTime = block.timestamp - 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                IDCAStrategy.InvalidFirstExecutionTime.selector, block.timestamp - 1, block.timestamp
            )
        );
        engine.createStrategy(params);
    }

    // ========================================================================
    // AUTHORIZATION TESTS
    // ========================================================================

    function test_authorization_nonOwnerCannotUpdate() public {
        vm.prank(alice);
        uint256 id = engine.createStrategy(_defaultParams());

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IDCAStrategy.NotStrategyOwner.selector, id, bob, alice));
        engine.updateStrategy(id, 20_000e18, 2 days, 6 hours, 200e18, 2000e18);
    }

    function test_authorization_nonOwnerCannotPause() public {
        vm.prank(alice);
        uint256 id = engine.createStrategy(_defaultParams());

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IDCAStrategy.NotStrategyOwner.selector, id, bob, alice));
        engine.pauseStrategy(id);
    }

    function test_authorization_nonOwnerCannotResume() public {
        vm.prank(alice);
        uint256 id = engine.createStrategy(_defaultParams());
        vm.prank(alice);
        engine.pauseStrategy(id);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IDCAStrategy.NotStrategyOwner.selector, id, bob, alice));
        engine.resumeStrategy(id);
    }

    function test_authorization_nonOwnerCannotCancel() public {
        vm.prank(alice);
        uint256 id = engine.createStrategy(_defaultParams());

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IDCAStrategy.NotStrategyOwner.selector, id, bob, alice));
        engine.cancelStrategy(id);
    }

    function test_nonExistentStrategy_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IDCAStrategy.StrategyNotFound.selector, 999));
        engine.getStrategy(999);

        vm.expectRevert(abi.encodeWithSelector(IDCAStrategy.StrategyNotFound.selector, 999));
        engine.getRemainingDelay(999);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDCAStrategy.StrategyNotFound.selector, 999));
        engine.updateStrategy(999, 1000e18, 1 days, 1 hours, 10e18, 100e18);
    }

    // ========================================================================
    // UPDATE TESTS
    // ========================================================================

    function test_updateStrategy_success() public {
        vm.prank(alice);
        uint256 id = engine.createStrategy(_defaultParams());

        vm.expectEmit(true, true, false, true);
        emit StrategyUpdated(id, alice, 25_000e18, 2 days, 8 hours, 250e18, 2500e18);

        vm.prank(alice);
        engine.updateStrategy(id, 25_000e18, 2 days, 8 hours, 250e18, 2500e18);

        IDCAStrategy.Strategy memory strategy = engine.getStrategy(id);
        // Modifiable fields updated
        assertEq(strategy.targetAllocation, 25_000e18);
        assertEq(strategy.frequency, 2 days);
        assertEq(strategy.maxDelay, 8 hours);
        assertEq(strategy.minExecutionAmount, 250e18);
        assertEq(strategy.maxExecutionAmount, 2500e18);

        // Immutable fields preserved
        assertEq(strategy.owner, alice);
        assertEq(strategy.inputToken, tokenA);
        assertEq(strategy.targetToken, tokenB);
        assertEq(strategy.nextExecutionTime, block.timestamp);
        assertTrue(strategy.status == IDCAStrategy.StrategyStatus.ACTIVE);
    }

    function test_updateStrategy_canUpdateWhilePaused() public {
        vm.prank(alice);
        uint256 id = engine.createStrategy(_defaultParams());
        vm.prank(alice);
        engine.pauseStrategy(id);

        vm.prank(alice);
        engine.updateStrategy(id, 30_000e18, 3 days, 12 hours, 300e18, 3000e18);

        IDCAStrategy.Strategy memory strategy = engine.getStrategy(id);
        assertEq(strategy.targetAllocation, 30_000e18);
        assertTrue(strategy.status == IDCAStrategy.StrategyStatus.PAUSED);
    }

    function test_updateStrategy_revert_whenCancelled() public {
        vm.prank(alice);
        uint256 id = engine.createStrategy(_defaultParams());
        vm.prank(alice);
        engine.cancelStrategy(id);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDCAStrategy.StrategyAlreadyCancelled.selector, id));
        engine.updateStrategy(id, 20_000e18, 2 days, 6 hours, 200e18, 2000e18);
    }

    // ========================================================================
    // STATE TRANSITIONS TESTS
    // ========================================================================

    function test_stateTransition_pauseAndResume() public {
        vm.prank(alice);
        uint256 id = engine.createStrategy(_defaultParams());

        // ACTIVE -> PAUSED
        vm.expectEmit(true, true, false, false);
        emit StrategyPaused(id, alice);
        vm.prank(alice);
        engine.pauseStrategy(id);
        assertEq(uint256(engine.getStrategy(id).status), uint256(IDCAStrategy.StrategyStatus.PAUSED));

        // PAUSED -> ACTIVE
        vm.expectEmit(true, true, false, false);
        emit StrategyResumed(id, alice);
        vm.prank(alice);
        engine.resumeStrategy(id);
        assertEq(uint256(engine.getStrategy(id).status), uint256(IDCAStrategy.StrategyStatus.ACTIVE));
    }

    function test_stateTransition_cancelFromActive() public {
        vm.prank(alice);
        uint256 id = engine.createStrategy(_defaultParams());

        vm.expectEmit(true, true, false, false);
        emit StrategyCancelled(id, alice);
        vm.prank(alice);
        engine.cancelStrategy(id);
        assertEq(uint256(engine.getStrategy(id).status), uint256(IDCAStrategy.StrategyStatus.CANCELLED));
    }

    function test_stateTransition_cancelFromPaused() public {
        vm.prank(alice);
        uint256 id = engine.createStrategy(_defaultParams());
        vm.prank(alice);
        engine.pauseStrategy(id);

        vm.expectEmit(true, true, false, false);
        emit StrategyCancelled(id, alice);
        vm.prank(alice);
        engine.cancelStrategy(id);
        assertEq(uint256(engine.getStrategy(id).status), uint256(IDCAStrategy.StrategyStatus.CANCELLED));
    }

    function test_stateTransition_invalidTransitions() public {
        vm.prank(alice);
        uint256 id = engine.createStrategy(_defaultParams());

        // Cannot resume an ACTIVE strategy
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDCAStrategy.InvalidStrategyStatus.selector,
                id,
                IDCAStrategy.StrategyStatus.ACTIVE,
                IDCAStrategy.StrategyStatus.PAUSED
            )
        );
        engine.resumeStrategy(id);

        // Pause
        vm.prank(alice);
        engine.pauseStrategy(id);

        // Cannot pause a PAUSED strategy
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDCAStrategy.InvalidStrategyStatus.selector,
                id,
                IDCAStrategy.StrategyStatus.PAUSED,
                IDCAStrategy.StrategyStatus.ACTIVE
            )
        );
        engine.pauseStrategy(id);

        // Cancel
        vm.prank(alice);
        engine.cancelStrategy(id);

        // Cannot cancel a CANCELLED strategy
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDCAStrategy.StrategyAlreadyCancelled.selector, id));
        engine.cancelStrategy(id);

        // Cannot resume a CANCELLED strategy
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDCAStrategy.InvalidStrategyStatus.selector,
                id,
                IDCAStrategy.StrategyStatus.CANCELLED,
                IDCAStrategy.StrategyStatus.PAUSED
            )
        );
        engine.resumeStrategy(id);

        // Cannot pause a CANCELLED strategy
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDCAStrategy.InvalidStrategyStatus.selector,
                id,
                IDCAStrategy.StrategyStatus.CANCELLED,
                IDCAStrategy.StrategyStatus.ACTIVE
            )
        );
        engine.pauseStrategy(id);
    }

    // ========================================================================
    // SCHEDULING & TIMING STATES TESTS
    // ========================================================================

    function test_timingStates_executionWindowLifecycle() public {
        uint256 firstTime = block.timestamp + 1000; // t = 1_001_000
        uint256 maxDelay = 200; // window: [1_001_000, 1_001_200]

        IDCAStrategy.StrategyParams memory params = _defaultParams();
        params.firstExecutionTime = firstTime;
        params.maxDelay = maxDelay;

        vm.prank(alice);
        uint256 id = engine.createStrategy(params);

        // 1. BEFORE DUE (t = 1_000_500)
        vm.warp(firstTime - 500);
        assertFalse(engine.isExecutionDue(id), "Should not be due before nextExecutionTime");
        assertFalse(engine.isExecutionWindowOpen(id), "Window should not be open before nextExecutionTime");
        assertFalse(engine.isOverdue(id), "Should not be overdue before nextExecutionTime");
        assertEq(engine.getRemainingDelay(id), maxDelay, "Remaining delay should be maxDelay before start");

        // 2. AT NEXT EXECUTION TIME (t = 1_001_000)
        vm.warp(firstTime);
        assertTrue(engine.isExecutionDue(id), "Should be due at nextExecutionTime");
        assertTrue(engine.isExecutionWindowOpen(id), "Window should be open at nextExecutionTime");
        assertFalse(engine.isOverdue(id), "Should not be overdue at nextExecutionTime");
        assertEq(engine.getRemainingDelay(id), maxDelay, "Remaining delay should be maxDelay at start");

        // 3. MID EXECUTION WINDOW (t = 1_001_050)
        vm.warp(firstTime + 50);
        assertTrue(engine.isExecutionDue(id), "Should be due in window");
        assertTrue(engine.isExecutionWindowOpen(id), "Window should be open in window");
        assertFalse(engine.isOverdue(id), "Should not be overdue in window");
        assertEq(engine.getRemainingDelay(id), 150, "Remaining delay should be 150");

        // 4. AT WINDOW END DEADLINE (t = 1_001_200)
        vm.warp(firstTime + maxDelay);
        assertTrue(engine.isExecutionDue(id), "Should be due at deadline");
        assertTrue(engine.isExecutionWindowOpen(id), "Window should be open at boundary");
        assertFalse(engine.isOverdue(id), "Should not be overdue at boundary");
        assertEq(engine.getRemainingDelay(id), 0, "Remaining delay should be 0 at deadline");

        // 5. OVERDUE (t = 1_001_201)
        vm.warp(firstTime + maxDelay + 1);
        assertTrue(engine.isExecutionDue(id), "Should be due (past scheduled time)");
        assertFalse(engine.isExecutionWindowOpen(id), "Window should be closed when overdue");
        assertTrue(engine.isOverdue(id), "Should be overdue past maxDelay");
        assertEq(engine.getRemainingDelay(id), 0, "Remaining delay should be 0 when overdue");
    }

    function test_timingStates_inactiveStrategiesReturnFalse() public {
        uint256 firstTime = block.timestamp;
        IDCAStrategy.StrategyParams memory params = _defaultParams();
        params.firstExecutionTime = firstTime;

        vm.prank(alice);
        uint256 id = engine.createStrategy(params);

        // Pause strategy
        vm.prank(alice);
        engine.pauseStrategy(id);

        assertFalse(engine.isExecutionDue(id), "Paused strategy should not be due");
        assertFalse(engine.isExecutionWindowOpen(id), "Paused strategy window should not be open");
        assertFalse(engine.isOverdue(id), "Paused strategy should not report overdue");

        // Cancel strategy
        vm.prank(alice);
        engine.cancelStrategy(id);

        assertFalse(engine.isExecutionDue(id), "Cancelled strategy should not be due");
        assertFalse(engine.isExecutionWindowOpen(id), "Cancelled strategy window should not be open");
        assertFalse(engine.isOverdue(id), "Cancelled strategy should not report overdue");
    }

    // ========================================================================
    // EXECUTION AMOUNT VALIDATION TESTS
    // ========================================================================

    function test_isValidExecutionAmount_constraints() public {
        IDCAStrategy.StrategyParams memory params = _defaultParams();
        params.minExecutionAmount = 100e18;
        params.maxExecutionAmount = 1000e18;
        params.targetAllocation = 5000e18;

        vm.prank(alice);
        uint256 id = engine.createStrategy(params);

        // Valid amounts
        assertTrue(engine.isValidExecutionAmount(id, 100e18), "Min amount should be valid");
        assertTrue(engine.isValidExecutionAmount(id, 500e18), "Mid amount should be valid");
        assertTrue(engine.isValidExecutionAmount(id, 1000e18), "Max amount should be valid");

        // Invalid amounts
        assertFalse(engine.isValidExecutionAmount(id, 0), "Zero amount should be invalid");
        assertFalse(engine.isValidExecutionAmount(id, 99e18), "Below min amount should be invalid");
        assertFalse(engine.isValidExecutionAmount(id, 1001e18), "Above max amount should be invalid");
        assertFalse(engine.isValidExecutionAmount(id, 6000e18), "Above targetAllocation should be invalid");

        // Inactive strategies return false
        vm.prank(alice);
        engine.pauseStrategy(id);
        assertFalse(engine.isValidExecutionAmount(id, 500e18), "Paused strategy should return false");

        vm.prank(alice);
        engine.cancelStrategy(id);
        assertFalse(engine.isValidExecutionAmount(id, 500e18), "Cancelled strategy should return false");

        // Non-existent strategy returns false
        assertFalse(engine.isValidExecutionAmount(999, 500e18), "Non-existent strategy should return false");
    }

    // ========================================================================
    // FUZZ TESTING
    // ========================================================================

    function testFuzz_createStrategy_validParameters(
        uint256 targetAllocation,
        uint256 frequency,
        uint256 maxDelay,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 delayStart
    ) public {
        // Bound fuzz values to realistic ranges
        targetAllocation = bound(targetAllocation, 1000e18, 1_000_000_000e18);
        frequency = bound(frequency, 1 minutes, 365 days);
        maxDelay = bound(maxDelay, 1 minutes, 30 days);
        minAmount = bound(minAmount, 1e18, targetAllocation);
        maxAmount = bound(maxAmount, minAmount, targetAllocation);
        delayStart = bound(delayStart, 0, 30 days);

        uint256 firstExecutionTime = delayStart == 0 ? 0 : block.timestamp + delayStart;

        IDCAStrategy.StrategyParams memory params = IDCAStrategy.StrategyParams({
            inputToken: tokenA,
            targetToken: tokenB,
            targetAllocation: targetAllocation,
            frequency: frequency,
            maxDelay: maxDelay,
            minExecutionAmount: minAmount,
            maxExecutionAmount: maxAmount,
            firstExecutionTime: firstExecutionTime
        });

        vm.prank(alice);
        uint256 id = engine.createStrategy(params);

        IDCAStrategy.Strategy memory strategy = engine.getStrategy(id);
        assertEq(strategy.targetAllocation, targetAllocation);
        assertEq(strategy.frequency, frequency);
        assertEq(strategy.maxDelay, maxDelay);
        assertEq(strategy.minExecutionAmount, minAmount);
        assertEq(strategy.maxExecutionAmount, maxAmount);
        assertEq(strategy.nextExecutionTime, firstExecutionTime == 0 ? block.timestamp : firstExecutionTime);
        assertTrue(strategy.status == IDCAStrategy.StrategyStatus.ACTIVE);
    }

    function testFuzz_isValidExecutionAmount(uint256 amount) public {
        uint256 min = 100e18;
        uint256 max = 1000e18;
        uint256 alloc = 5000e18;

        IDCAStrategy.StrategyParams memory params = _defaultParams();
        params.minExecutionAmount = min;
        params.maxExecutionAmount = max;
        params.targetAllocation = alloc;

        vm.prank(alice);
        uint256 id = engine.createStrategy(params);

        bool valid = engine.isValidExecutionAmount(id, amount);
        if (amount >= min && amount <= max && amount <= alloc && amount > 0) {
            assertTrue(valid, "Should be valid within bounds");
        } else {
            assertFalse(valid, "Should be invalid outside bounds");
        }
    }
}
