import { Router } from "express";
import { getDecision } from "../services/decision.service";
import { getStrategy } from "../services/strategy.service";

const router = Router();

// POST /api/decision/:strategyId
router.post("/:strategyId", async (req, res, next) => {
  try {
    const { strategyId } = req.params;
    
    const strategy = await getStrategy(strategyId);
    if (!strategy) {
      return res.status(404).json({ error: "Strategy not found" });
    }
    
    if (strategy.status !== 1) { // 1 = ACTIVE
       return res.status(409).json({ error: "Strategy is not active" });
    }

    const decision = await getDecision(strategyId);
    
    if (!decision) {
      return res.status(500).json({ error: "Failed to evaluate decision" });
    }

    res.json({ decision });
  } catch (error) {
    next(error);
  }
});

export default router;
