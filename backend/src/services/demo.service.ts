import { ethers } from "ethers";
import { provider, contracts } from "../contracts/provider";
import { runOnce } from "./scheduler.service";

export type DemoState = 'INITIAL' | 'DAY_0' | 'DAY_1' | 'DAY_2' | 'COMPLETED';

let currentState: DemoState = 'INITIAL';
let demoStrategyId: string | null = null;
let simulatedDay = -1;

export async function setupDemo(strategyId: string) {
    currentState = 'INITIAL';
    demoStrategyId = strategyId;
    simulatedDay = -1;
    return { status: "Demo setup initialized", strategyId };
}

export async function resetDemo() {
    currentState = 'INITIAL';
    demoStrategyId = null;
    simulatedDay = -1;
    return { status: "Demo reset" };
}

export async function getDemoStatus() {
    return {
        state: currentState,
        simulatedDay,
        strategyId: demoStrategyId
    };
}

export async function stepDemo() {
    if (!demoStrategyId) {
        throw new Error("Demo not initialized. Call /api/demo/setup first.");
    }
    
    if (currentState === 'COMPLETED') {
        throw new Error("Demo already completed.");
    }

    if (currentState === 'INITIAL') {
        currentState = 'DAY_0';
        simulatedDay = 0;
        await setPoorMarketConditions();
    } else if (currentState === 'DAY_0') {
        currentState = 'DAY_1';
        simulatedDay = 1;
        await advanceTime(86400); // Advance 1 day
        await setPoorMarketConditions();
    } else if (currentState === 'DAY_1') {
        currentState = 'DAY_2';
        simulatedDay = 2;
        await advanceTime(86400); // Advance 1 day
        await setImprovedMarketConditions();
    } else if (currentState === 'DAY_2') {
        currentState = 'COMPLETED';
        return getDemoStatus();
    }

    // Run scheduler evaluate/prepare for the demo strategy
    await runOnce();

    return {
        status: "Step advanced",
        state: currentState,
        simulatedDay,
        job: null
    };
}

async function advanceTime(seconds: number) {
    await provider.send("evm_increaseTime", [seconds]);
    await provider.send("evm_mine", []);
}

// 1e18 scaling for mock data
async function setPoorMarketConditions() {
    if (contracts.mockMarketProvider) {
        // High volatility, high price deviation
        const owner = new ethers.Wallet(
            "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", // Anvil account #0 private key for local demo
            provider
        );
        const providerWithSigner = contracts.mockMarketProvider.connect(owner) as ethers.Contract;
        const currentBlock = await provider.getBlock("latest");
        
        await providerWithSigner.setRawData({
            currentPrice: ethers.parseUnits("3000", 18),
            twap: ethers.parseUnits("2500", 18), // Big deviation
            volatility: ethers.parseUnits("0.4", 18), // 40% vol
            liquidity: ethers.parseUnits("1000", 6), // Low liquidity
            dataSource: ethers.id("MOCK_SIMULATED_MARKET_DATA"),
            timestamp: currentBlock?.timestamp || Math.floor(Date.now() / 1000)
        });
    }
}

async function setImprovedMarketConditions() {
    if (contracts.mockMarketProvider) {
        const owner = new ethers.Wallet(
            "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", // Anvil account #0
            provider
        );
        const providerWithSigner = contracts.mockMarketProvider.connect(owner) as ethers.Contract;
        const currentBlock = await provider.getBlock("latest");
        
        await providerWithSigner.setRawData({
            currentPrice: ethers.parseUnits("3000", 18),
            twap: ethers.parseUnits("2990", 18), // Low deviation
            volatility: ethers.parseUnits("0.05", 18), // 5% vol
            liquidity: ethers.parseUnits("1000000", 6), // High liquidity
            dataSource: ethers.id("MOCK_SIMULATED_MARKET_DATA"),
            timestamp: currentBlock?.timestamp || Math.floor(Date.now() / 1000)
        });
    }
}
