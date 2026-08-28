// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DCAEngine} from "../src/DCAEngine.sol";
import {YieldVault} from "../src/YieldVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockMarketDataProvider} from "../src/market/MockMarketDataProvider.sol";
import {MarketAnalyzer} from "../src/market/MarketAnalyzer.sol";
import {YieldAnalyzer} from "../src/yield/YieldAnalyzer.sol";
import {DecisionEngine} from "../src/decision/DecisionEngine.sol";
import {ExecutionManager} from "../src/execution/ExecutionManager.sol";
import {MockSwapExecutor} from "../src/mocks/MockSwapExecutor.sol";

/**
 * @title DeployDCA
 * @notice Deployment script for Modules 1–6 of the Yield-Aware DCA System.
 * @dev Deploys MockERC20 (USDC and WETH), DCAEngine, YieldVault, MockMarketDataProvider,
 *      MarketAnalyzer, YieldAnalyzer, DecisionEngine, MockSwapExecutor, and ExecutionManager.
 */
contract DeployDCA is Script {
    // Default Anvil Account #0 private key for local development
    uint256 internal constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function run()
        external
        returns (
            MockERC20 mockUSDC,
            MockERC20 mockWETH,
            DCAEngine engine,
            YieldVault vault,
            MockMarketDataProvider mockProvider,
            MarketAnalyzer marketAnalyzer,
            YieldAnalyzer yieldAnalyzer,
            DecisionEngine decisionEngine,
            MockSwapExecutor swapExecutor,
            ExecutionManager executionManager
        )
    {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", DEFAULT_ANVIL_KEY);
        address deployer = vm.addr(deployerKey);

        console2.log("Starting YieldDCA deployment (Modules 1-6)...");
        console2.log("Deployer address:", deployer);

        vm.startBroadcast(deployerKey);

        // 1. Deploy Mock Tokens
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        console2.log("MockERC20 (USDC) deployed at:", address(mockUSDC));

        mockWETH = new MockERC20("Wrapped Ether", "WETH", 18);
        console2.log("MockERC20 (WETH) deployed at:", address(mockWETH));

        // 2. Deploy Module 1: DCA Strategy Management Engine
        engine = new DCAEngine();
        console2.log("DCAEngine deployed at:", address(engine));

        // 3. Deploy Module 2: ERC-4626 Yield Vault
        vault = new YieldVault(IERC20(address(mockUSDC)), "Yield DCA Vault Share", "ydcaUSDC", deployer);
        console2.log("YieldVault deployed at:", address(vault));

        // 4. Deploy Module 3: Mock Market Data Provider
        mockProvider = new MockMarketDataProvider();
        console2.log("MockMarketDataProvider deployed at:", address(mockProvider));

        // 5. Deploy Module 3: Market Analyzer
        marketAnalyzer = new MarketAnalyzer(address(mockProvider));
        console2.log("MarketAnalyzer deployed at:", address(marketAnalyzer));

        // 6. Deploy Module 4: Yield Analyzer
        yieldAnalyzer = new YieldAnalyzer(address(vault), deployer);
        console2.log("YieldAnalyzer deployed at:", address(yieldAnalyzer));

        // 7. Deploy Module 5: Decision Engine
        decisionEngine = new DecisionEngine(deployer);
        console2.log("DecisionEngine deployed at:", address(decisionEngine));

        // 8. Deploy Mock Swap Executor (1:1 mock rate based on 6 decimals = 1e6)
        swapExecutor = new MockSwapExecutor(address(mockWETH), 1e6);
        console2.log("MockSwapExecutor deployed at:", address(swapExecutor));

        // Mint some WETH to the mock executor so it can pay out swaps
        mockWETH.mint(address(swapExecutor), 1_000_000e18);

        // 9. Deploy Module 6: Execution Manager
        executionManager = new ExecutionManager(deployer, address(engine), address(vault), address(swapExecutor));
        console2.log("ExecutionManager deployed at:", address(executionManager));

        // 10. Authorize ExecutionManager in YieldVault
        vault.setAuthorizedOperator(address(executionManager), true);
        console2.log("ExecutionManager authorized in YieldVault");

        vm.stopBroadcast();

        console2.log("Deployment complete! All Modules 1-6 deployed.");
    }
}
