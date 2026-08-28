import { contracts } from "../contracts/provider";

export async function getVaultState() {
  const [totalAssets, totalShares, simulatedAPY] = await contracts.yieldVault.getVaultState();
  return {
    totalAssets: totalAssets.toString(),
    totalShares: totalShares.toString(),
    simulatedAPY: simulatedAPY.toString(),
  };
}

export async function getUserVaultData(userAddress: string) {
  const [assets, shares] = await Promise.all([
    contracts.yieldVault.getUserAssets(userAddress),
    contracts.yieldVault.getUserShares(userAddress)
  ]);
  return {
    assets: assets.toString(),
    shares: shares.toString()
  };
}
