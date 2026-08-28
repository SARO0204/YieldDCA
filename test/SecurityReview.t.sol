// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ExecutionManager} from "../src/execution/ExecutionManager.sol";
import {IExecutionManager} from "../src/interfaces/IExecutionManager.sol";
import {IDecisionEngine} from "../src/interfaces/IDecisionEngine.sol";
import {IDCAStrategy} from "../src/interfaces/IDCAStrategy.sol";
import {DCAEngine} from "../src/DCAEngine.sol";
import {YieldVault} from "../src/YieldVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockSwapExecutor} from "../src/mocks/MockSwapExecutor.sol";

contract SecurityReviewTest is Test {
    MockERC20 public usdc;
    MockERC20 public weth;
    DCAEngine public dcaEngine;
    YieldVault public vault;
    MockSwapExecutor public swapExecutor;
    ExecutionManager public manager;

    address public deployer = address(this);
    address public alice = address(0xA11CE);

    uint256 constant INITIAL_USDC = 100_000e6;
    uint256 constant TARGET_ALLOCATION = 10_000e6;
    uint256 constant MIN_EXECUTION = 100e6;
    uint256 constant MAX_EXECUTION = 10_000e6;
    uint256 constant FREQ = 1 days;
    uint256 constant MAX_DELAY = 4 hours;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);

        dcaEngine = new DCAEngine();
        vault = new YieldVault(IERC20(address(usdc)), "Yield Vault", "yvUSDC", deployer);
        swapExecutor = new MockSwapExecutor(address(weth), 1e6);

        manager = new ExecutionManager(deployer, address(dcaEngine), address(vault), address(swapExecutor));

        vault.setAuthorizedOperator(address(manager), true);

        usdc.mint(alice, INITIAL_USDC);
        weth.mint(address(swapExecutor), 100_000e18);
    }

    function test_Security_InvalidInputToken_Reverts() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), INITIAL_USDC);
        vault.deposit(INITIAL_USDC, alice);

        // Strategy with WETH as input, but vault asset is USDC
        uint256 strategyId = dcaEngine.createStrategy(
            IDCAStrategy.StrategyParams({
                inputToken: address(weth),
                targetToken: address(usdc),
                targetAllocation: TARGET_ALLOCATION,
                frequency: FREQ,
                maxDelay: MAX_DELAY,
                minExecutionAmount: MIN_EXECUTION,
                maxExecutionAmount: MAX_EXECUTION,
                firstExecutionTime: 0
            })
        );
        vm.stopPrank();

        IDecisionEngine.DecisionDiagnostics memory diag;
        IDecisionEngine.DecisionResult memory decision = IDecisionEngine.DecisionResult({
            action: IDecisionEngine.DecisionAction.EXECUTE,
            targetAmount: TARGET_ALLOCATION,
            executionAmount: 1000e6,
            remainingAmount: TARGET_ALLOCATION - 1000e6,
            recommendedDelay: 0,
            score: 10000,
            reason: "Mock",
            timestamp: block.timestamp,
            diagnostics: diag
        });

        // Ensure state before execution
        uint256 preVaultBalance = usdc.balanceOf(address(vault));
        uint256 preNonce = manager.getExecutionNonce(strategyId);

        vm.startPrank(alice);
        vm.expectRevert(IExecutionManager.InvalidInputToken.selector);
        manager.executeDecision(strategyId, decision, 0, 0);

        vm.expectRevert(IExecutionManager.InvalidInputToken.selector);
        manager.validateExecution(strategyId, decision, 0);
        vm.stopPrank();

        // Ensure state unchanged
        assertEq(usdc.balanceOf(address(vault)), preVaultBalance);
        assertEq(manager.getExecutionNonce(strategyId), preNonce);
    }
}
