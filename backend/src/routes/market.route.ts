import { Router } from "express";
import { getMarketState } from "../services/market.service";
import { getStrategy } from "../services/strategy.service";

const router = Router();

// GET /api/market-state/:strategyId
router.get("/:strategyId", async (req, res, next) => {
  try {
    const { strategyId } = req.params;
    const strategy = await getStrategy(strategyId);
    if (!strategy) {
      return res.status(404).json({ error: "Strategy not found" });
    }

    const marketState = await getMarketState(strategy.targetAllocation);
    
    if (!marketState) {
      return res.status(404).json({ error: "Market data not found or invalid strategy" });
    }

    res.json({ marketState });
  } catch (error) {
    next(error);
  }
});

export default router;
