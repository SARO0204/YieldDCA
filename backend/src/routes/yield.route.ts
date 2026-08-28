import { Router } from "express";
import { getYieldAnalysisForStrategy } from "../services/yield.service";

const router = Router();

// GET /api/yield-analysis/:strategyId
router.get("/:strategyId", async (req, res, next) => {
  try {
    const { strategyId } = req.params;
    const yieldAnalysis = await getYieldAnalysisForStrategy(strategyId);
    
    if (!yieldAnalysis) {
      return res.status(404).json({ error: "Yield analysis not found or invalid strategy" });
    }

    res.json({ yieldAnalysis });
  } catch (error) {
    next(error);
  }
});

export default router;
