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

/**
 * @title DeployDCA
 * @notice Deployment script for Modules 1–4 of the Yield-Aware DCA System.
 * @dev Deploys MockERC20 (USDC), DCAEngine, YieldVault, MockMarketDataProvider,
 *      MarketAnalyzer, and YieldAnalyzer using private key from environment variables.
 */
contract DeployDCA is Script {
    // Default Anvil Account #0 private key for local development
    uint256 internal constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function run()
        external
        returns (
            MockERC20 mockUSDC,
            DCAEngine engine,
            YieldVault vault,
            MockMarketDataProvider mockProvider,
            MarketAnalyzer marketAnalyzer,
            YieldAnalyzer yieldAnalyzer
        )
    {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", DEFAULT_ANVIL_KEY);
        address deployer = vm.addr(deployerKey);

        console2.log("Starting YieldDCA deployment (Modules 1-4)...");
        console2.log("Deployer address:", deployer);

        vm.startBroadcast(deployerKey);

        // 1. Deploy Mock Underlying Token (USDC, 6 decimals)
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        console2.log("MockERC20 (USDC) deployed at:", address(mockUSDC));

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
        yieldAnalyzer = new YieldAnalyzer(address(vault), msg.sender);
        console2.log("YieldAnalyzer deployed at:", address(yieldAnalyzer));

        vm.stopBroadcast();

        console2.log("Deployment complete! All Modules 1-4 deployed.");
    }
}
