import express from "express";
import cors from "cors";
import { loadConfig } from "./config";
import dashboardRoute from "./routes/dashboard.route";
import { errorHandler } from "./middleware/errorHandler";

const config = loadConfig();
const app = express();

app.use(cors());
app.use(express.json());

// Health Check
app.get("/api/health", (req, res) => {
  res.json({ status: "ok", timestamp: Date.now() });
});

// Routes
app.use("/api/dashboard", dashboardRoute);

// Global Error Handler
app.use(errorHandler);

app.listen(config.port, () => {
  console.log(`Backend API running on http://localhost:${config.port}`);
});
