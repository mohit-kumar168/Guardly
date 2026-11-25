import type { Response } from "express";

/**
 * Standardized API Response structure for consistent API outputs.
 */
export class ApiResponse<T = unknown> {
  public readonly statusCode: number;
  public readonly data: T;
  public readonly message: string;
  public readonly success: boolean;

  constructor(statusCode: number, data: T, message = "Success") {
    this.statusCode = statusCode;
    this.data = data;
    this.message = message;
    this.success = statusCode < 400;
  }

  /**
   * Helper to send this response directly through Express response object.
   */
  public send(res: Response): Response {
    return res.status(this.statusCode).json({
      success: this.success,
      statusCode: this.statusCode,
      message: this.message,
      data: this.data,
    });
  }

  static success<T>(data: T, message = "Success", statusCode = 200): ApiResponse<T> {
    return new ApiResponse(statusCode, data, message);
  }

  static created<T>(data: T, message = "Resource created successfully"): ApiResponse<T> {
    return new ApiResponse(201, data, message);
  }
}
