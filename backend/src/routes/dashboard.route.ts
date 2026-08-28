import { Router } from "express";
import { getDashboardData } from "../services/dashboard.service";
import { insertMarketSnapshot, insertYieldSnapshot } from "../db/database";

const router = Router();

router.get("/", async (req, res, next) => {
  try {
    const userAddress = req.query.user as string;
    const strategyId = req.query.strategy as string;
    
    const dashboardData = await getDashboardData(userAddress, strategyId);
    
    // Optionally snapshot the market and yield data
    if (dashboardData.market) {
      insertMarketSnapshot(dashboardData.market);
    }
    if (dashboardData.vault) {
      insertYieldSnapshot(dashboardData.vault);
    }

    res.json(dashboardData);
  } catch (error) {
    next(error);
  }
});

export default router;
