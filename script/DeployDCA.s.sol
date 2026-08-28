// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {DCAEngine} from "../src/DCAEngine.sol";

/**
 * @title DeployDCA
 * @notice Deployment script for Module 1 (DCA Strategy Management).
 * @dev Deploys the DCAEngine contract using a private key read from environment variables
 *      or falling back to the standard local Anvil development key.
 */
contract DeployDCA is Script {
    // Default Anvil Account #0 private key for local development
    uint256 internal constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function run() external returns (DCAEngine engine) {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", DEFAULT_ANVIL_KEY);

        console2.log("Starting DCAEngine deployment...");
        console2.log("Deployer address:", vm.addr(deployerKey));

        vm.startBroadcast(deployerKey);

        engine = new DCAEngine();

        vm.stopBroadcast();

        console2.log("DCAEngine successfully deployed at:", address(engine));
    }
}
