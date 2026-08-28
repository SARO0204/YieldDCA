import { Router } from "express";
import { contracts } from "../contracts/provider";
import { getDecision } from "../services/decision.service";
import { getExecutionRecord, getRemainingAllocation } from "../services/execution.service";
import { getStrategy } from "../services/strategy.service";
import { insertExecutionRecord, getExecutionHistory } from "../db/database";

const router = Router();

// POST /api/execution/:strategyId
router.post("/:strategyId", async (req, res, next) => {
  try {
    const { strategyId } = req.params;
    
    // 1. Revalidate Strategy
    const strategy = await getStrategy(strategyId);
    if (!strategy) {
      return res.status(404).json({ error: "Strategy not found" });
    }
    
    if (strategy.status !== 1) { // 1 = ACTIVE
       return res.status(409).json({ error: "Strategy is not active" });
    }

    // 2. Obtain Decision Result
    const decision = await getDecision(strategyId);
    if (!decision) {
      return res.status(500).json({ error: "Failed to evaluate decision" });
    }

    // Convert decision back to tuple expected by validateExecution
    // DecisionAction enum: NONE=0, EXECUTE=1, PARTIAL_EXECUTION=2, DELAY=3
    const decisionResultTuple = {
      action: decision.action,
      targetAmount: decision.targetAmount,
      executionAmount: decision.executionAmount,
      remainingAmount: decision.remainingAmount,
      recommendedDelay: decision.recommendedDelay,
      score: decision.score,
      reason: decision.reason,
      timestamp: decision.timestamp,
      diagnostics: decision.diagnostics // assuming it accepts this form, though usually Solidity expects tuple. Wait, validateExecution might expect an array or specific object keys.
    };

    // 3. Obtain current nonce
    const executionRecord = await getExecutionRecord(strategyId);
    const expectedNonce = executionRecord.nonce;

    // 4. Pre-flight Validation through existing on-chain logic (Module 8)
    // Try calling validateExecution (read-only)
    try {
      const [validatedAmount, remainingAfter] = await contracts.executionManager.validateExecution(
        strategyId,
        decisionResultTuple,
        expectedNonce
      );
      
      // If validation succeeds, prepare transaction
      // For slippage, we would need to pass minSwapOutput. For now, pass 0 or a user-provided value.
      const minSwapOutput = req.body.minSwapOutput || "0";

      const tx = await contracts.executionManager.executeDecision.populateTransaction(
        strategyId,
        decisionResultTuple,
        expectedNonce,
        minSwapOutput
      );

      // Record to history as a "PREPARED" transaction
      insertExecutionRecord({
        strategyId,
        action: decision.action,
        requestedAmount: decision.executionAmount,
        nonce: expectedNonce,
        status: "PREPARED",
        timestamp: Math.floor(Date.now() / 1000)
      });

      return res.json({
        message: "Transaction prepared successfully",
        validation: {
          validatedAmount: validatedAmount.toString(),
          remainingAfter: remainingAfter.toString()
        },
        transaction: {
          to: tx.to,
          data: tx.data,
          value: tx.value?.toString() || "0"
        }
      });
      
    } catch (err: any) {
      // Revert from validateExecution
      console.error("validateExecution reverted:", err);
      return res.status(422).json({
        error: "Execution validation failed on-chain",
        details: err.reason || err.message
      });
    }
  } catch (error) {
    next(error);
  }
});

// GET /api/executions/:strategyId
router.get("/:strategyId", async (req, res, next) => {
  try {
    const { strategyId } = req.params;
    const history = getExecutionHistory(strategyId);
    res.json({ history });
  } catch (error) {
    next(error);
  }
});

export default router;
