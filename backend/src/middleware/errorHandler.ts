import { Request, Response, NextFunction } from "express";

export function errorHandler(err: any, req: Request, res: Response, next: NextFunction) {
  console.error("Backend Error:", err);
  
  if (err.code === 'CALL_EXCEPTION') {
    return res.status(400).json({ error: "Contract call failed", details: err.message });
  }

  if (err.code === 'BAD_DATA') {
    return res.status(503).json({ error: "Blockchain State Error", details: "Could not decode contract data. The contract may not be deployed at the configured address." });
  }

  if (err.code === 'ECONNREFUSED' || (err.message && err.message.includes('ECONNREFUSED'))) {
    return res.status(503).json({ error: "Blockchain Connection Error", details: "Could not connect to the RPC node." });
  }
  
  res.status(500).json({
    error: "Internal Server Error",
    message: process.env.NODE_ENV === 'development' ? err.message : "An unexpected error occurred."
  });
}
