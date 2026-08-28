import { Router } from "express";
import { setupDemo, stepDemo, getDemoStatus, resetDemo } from "../services/demo.service";

const router = Router();

router.post("/setup", async (req, res, next) => {
    try {
        const { strategyId } = req.body;
        if (!strategyId) {
            return res.status(400).json({ error: "strategyId is required" });
        }
        const result = await setupDemo(strategyId);
        res.json(result);
    } catch (err) {
        next(err);
    }
});

router.post("/step", async (req, res, next) => {
    try {
        const result = await stepDemo();
        res.json(result);
    } catch (err) {
        next(err);
    }
});

router.get("/status", async (req, res, next) => {
    try {
        const result = await getDemoStatus();
        res.json(result);
    } catch (err) {
        next(err);
    }
});

router.post("/reset", async (req, res, next) => {
    try {
        const result = await resetDemo();
        res.json(result);
    } catch (err) {
        next(err);
    }
});

export default router;
