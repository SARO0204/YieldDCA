import { Router } from "express";
import { getSchedulerStatus } from "../services/scheduler.service";
import { getAllSchedulerJobs, getSchedulerJob } from "../db/database";

const router = Router();

router.get("/status", (req, res) => {
  res.json(getSchedulerStatus());
});

router.get("/jobs", (req, res) => {
  const jobs = getAllSchedulerJobs();
  res.json(jobs);
});

router.get("/jobs/:jobId", (req, res) => {
  const job = getSchedulerJob(req.params.jobId);
  if (!job) {
    return res.status(404).json({ error: "Job not found" });
  }
  res.json(job);
});

export default router;
