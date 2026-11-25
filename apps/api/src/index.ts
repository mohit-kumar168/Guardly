import express from "express";
import cookieParser from "cookie-parser";
import { env } from "./config/env";
import { logger } from "./config/logger";
import { prisma } from "./db/prisma";
import { requestLogger } from "./middleware/request_logger.middleware";
import { errorHandler, notFoundHandler } from "./middleware/error.middleware";
import { ApiResponse } from "./utils/apiResponse";

export const app = express();

// Standard middlewares
app.use(requestLogger);
app.use(express.json({ limit: "16kb" }));
app.use(express.urlencoded({ extended: true, limit: "16kb" }));
app.use(cookieParser());

// Base health check endpoint
app.get("/health", (_req, res) => {
  return ApiResponse.success(
    {
      service: "guardly-api",
      environment: env.NODE_ENV,
      timestamp: new Date().toISOString(),
    },
    "Guardly API is healthy"
  ).send(res);
});

// 404 handler for unmatched routes
app.use(notFoundHandler);

// Centralized error handler
app.use(errorHandler);

// Server startup
export const server = app.listen(env.PORT, () => {
  logger.info(
    `Guardly API server is running in ${env.NODE_ENV} mode on port ${env.PORT}`
  );
});

server.on("error", (err: NodeJS.ErrnoException) => {
  if (err.code === "EADDRINUSE") {
    logger.error(
      `Port ${env.PORT} is already in use. Please free port ${env.PORT} or change PORT in .env`
    );
  } else {
    logger.error(err, "Server encountered a fatal error during startup");
  }
  process.exit(1);
});

// Graceful shutdown handling
const gracefulShutdown = async (signal: string) => {
  logger.info(`Received ${signal}. Initiating graceful shutdown...`);

  server.close(async () => {
    logger.info("HTTP server closed.");
    try {
      await prisma.$disconnect();
      logger.info("Database connection disconnected cleanly.");
      process.exit(0);
    } catch (error) {
      logger.error(error, "Error during database disconnection during shutdown.");
      process.exit(1);
    }
  });

  // Force close if graceful shutdown takes too long
  setTimeout(() => {
    logger.error("Forced shutdown after timeout.");
    process.exit(1);
  }, 10000).unref();
};

process.on("SIGTERM", () => gracefulShutdown("SIGTERM"));
process.on("SIGINT", () => gracefulShutdown("SIGINT"));
