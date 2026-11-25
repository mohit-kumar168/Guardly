import type { Request, Response, NextFunction, ErrorRequestHandler } from "express";
import { ApiError } from "../utils/apiError";
import { env } from "../config/env";
import { logger } from "../config/logger";

/**
 * 404 Route Not Found Middleware.
 */
export const notFoundHandler = (
  req: Request,
  _res: Response,
  next: NextFunction
): void => {
  next(ApiError.notFound(`Route not found: ${req.method} ${req.originalUrl}`));
};

/**
 * Global Centralized Error Handling Middleware.
 */
export const errorHandler: ErrorRequestHandler = (
  err: any,
  _req: Request,
  res: Response,
  _next: NextFunction
): void => {
  // If the error is an operational ApiError
  if (err instanceof ApiError) {
    res.status(err.statusCode).json({
      success: false,
      statusCode: err.statusCode,
      message: err.message,
      errors: err.errors,
      ...(env.NODE_ENV === "development" ? { stack: err.stack } : {}),
    });
    return;
  }

  // Handle malformed JSON body from express.json()
  if (err.type === "entity.parse.failed" || (err instanceof SyntaxError && "body" in err)) {
    res.status(400).json({
      success: false,
      statusCode: 400,
      message: "Malformed JSON payload in request body",
      errors: [],
    });
    return;
  }

  // Handle other unexpected errors
  logger.error(err, "Unhandled application error");

  const statusCode = typeof err.statusCode === "number" ? err.statusCode : 500;
  const isProd = env.NODE_ENV === "production";

  res.status(statusCode).json({
    success: false,
    statusCode,
    message: isProd ? "Internal Server Error" : err.message || "Internal Server Error",
    errors: [],
    ...(!isProd ? { stack: err.stack } : {}),
  });
};
