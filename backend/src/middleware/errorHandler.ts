import { Request, Response, NextFunction } from "express";

export function errorHandler(err: any, req: Request, res: Response, next: NextFunction) {
  console.error("Backend Error:", err);
  
  if (err.code === 'CALL_EXCEPTION') {
    return res.status(400).json({ error: "Contract call failed", details: err.message });
  }
  
  res.status(500).json({
    error: "Internal Server Error",
    message: err.message || "An unknown error occurred"
  });
}
