import { Router } from "express";
import { contracts } from "../contracts/provider";
import { getStrategy, getUserStrategies } from "../services/strategy.service";
import { isAddress } from "ethers";

const router = Router();

// POST /api/strategies
// Returns transaction parameters to create a strategy
router.post("/", async (req, res, next) => {
  try {
    const {
      inputToken,
      targetToken,
      targetAllocation,
      frequency,
      maxDelay,
      minExecutionAmount,
      maxExecutionAmount,
      firstExecutionTime
    } = req.body;

    if (!isAddress(inputToken) || !isAddress(targetToken)) {
      return res.status(400).json({ error: "Invalid token address" });
    }

    const params = {
      inputToken,
      targetToken,
      targetAllocation: targetAllocation?.toString(),
      frequency: frequency?.toString(),
      maxDelay: maxDelay?.toString(),
      minExecutionAmount: minExecutionAmount?.toString(),
      maxExecutionAmount: maxExecutionAmount?.toString(),
      firstExecutionTime: firstExecutionTime ? firstExecutionTime.toString() : "0"
    };

    const tx = await contracts.dcaEngine.createStrategy.populateTransaction(params);

    res.json({
      message: "Transaction prepared",
      transaction: {
        to: tx.to,
        data: tx.data,
        value: tx.value?.toString() || "0"
      }
    });
  } catch (error) {
    next(error);
  }
});

// GET /api/strategies/user/:user
router.get("/user/:user", async (req, res, next) => {
  try {
    const user = req.params.user;
    if (!isAddress(user)) {
      return res.status(400).json({ error: "Invalid user address" });
    }
    const strategies = await getUserStrategies(user);
    res.json({ strategies });
  } catch (error) {
    next(error);
  }
});

// GET /api/strategies/:id
router.get("/:id", async (req, res, next) => {
  try {
    const id = req.params.id;
    const strategy = await getStrategy(id);
    if (!strategy) {
      return res.status(404).json({ error: "Strategy not found" });
    }
    res.json({ strategy });
  } catch (error) {
    next(error);
  }
});

// PUT /api/strategies/:id
router.put("/:id", async (req, res, next) => {
  try {
    const id = req.params.id;
    const {
      targetAllocation,
      frequency,
      maxDelay,
      minExecutionAmount,
      maxExecutionAmount
    } = req.body;

    const tx = await contracts.dcaEngine.updateStrategy.populateTransaction(
      id,
      targetAllocation?.toString(),
      frequency?.toString(),
      maxDelay?.toString(),
      minExecutionAmount?.toString(),
      maxExecutionAmount?.toString()
    );

    res.json({
      message: "Transaction prepared",
      transaction: {
        to: tx.to,
        data: tx.data,
        value: tx.value?.toString() || "0"
      }
    });
  } catch (error) {
    next(error);
  }
});

// POST /api/strategies/:id/pause
router.post("/:id/pause", async (req, res, next) => {
  try {
    const id = req.params.id;
    const tx = await contracts.dcaEngine.pauseStrategy.populateTransaction(id);
    res.json({
      message: "Transaction prepared",
      transaction: {
        to: tx.to,
        data: tx.data,
        value: tx.value?.toString() || "0"
      }
    });
  } catch (error) {
    next(error);
  }
});

// POST /api/strategies/:id/resume
router.post("/:id/resume", async (req, res, next) => {
  try {
    const id = req.params.id;
    const tx = await contracts.dcaEngine.resumeStrategy.populateTransaction(id);
    res.json({
      message: "Transaction prepared",
      transaction: {
        to: tx.to,
        data: tx.data,
        value: tx.value?.toString() || "0"
      }
    });
  } catch (error) {
    next(error);
  }
});

export default router;
