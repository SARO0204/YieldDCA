import express from "express";
import cors from "cors";
import { loadConfig } from "./config";
import dashboardRoute from "./routes/dashboard.route";
import strategyRoute from "./routes/strategy.route";
import marketRoute from "./routes/market.route";
import yieldRoute from "./routes/yield.route";
import decisionRoute from "./routes/decision.route";
import executionRoute from "./routes/execution.route";
import schedulerRoute from "./routes/scheduler.route";
import { errorHandler } from "./middleware/errorHandler";
import { startScheduler } from "./services/scheduler.service";

const config = loadConfig();
export const app = express();

// Handle BigInt serialization for JSON responses
(BigInt.prototype as any).toJSON = function () {
  return this.toString();
};

app.use(cors());
app.use(express.json());

// Health Check
app.get("/api/health", (req, res) => {
  res.json({ status: "ok", timestamp: Date.now() });
});

import demoRoute from "./routes/demo.route";

app.use("/api/dashboard", dashboardRoute);
app.use("/api/strategies", strategyRoute);
app.use("/api/market-state", marketRoute);
app.use("/api/yield-analysis", yieldRoute);
app.use("/api/decision", decisionRoute);
app.use("/api/execution", executionRoute);
app.use("/api/executions", executionRoute); // Reuse same route file for GET history
app.use("/api/scheduler", schedulerRoute);
app.use("/api/demo", demoRoute);

// Global Error Handler
app.use(errorHandler);

if (require.main === module) {
  app.listen(config.port, () => {
    console.log(`Backend API running on http://localhost:${config.port}`);
    if (config.scheduler.enabled) {
      startScheduler();
    }
  });
}
