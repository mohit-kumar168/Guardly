/**
 * Standardized API Error class for operational errors.
 */
export class ApiError extends Error {
  public readonly statusCode: number;
  public readonly errors: unknown[];
  public readonly success: boolean = false;
  public readonly isOperational: boolean = true;
  public readonly data: unknown = null;

  constructor(
    statusCode: number,
    message: string = "Something went wrong",
    errors: unknown[] = [],
    stack: string = ""
  ) {
    super(message);
    this.statusCode = statusCode;
    this.errors = errors;

    if (stack) {
      this.stack = stack;
    } else if (Error.captureStackTrace) {
      Error.captureStackTrace(this, this.constructor);
    }
  }

  static badRequest(message = "Bad Request", errors: unknown[] = []): ApiError {
    return new ApiError(400, message, errors);
  }

  static unauthorized(message = "Unauthorized", errors: unknown[] = []): ApiError {
    return new ApiError(401, message, errors);
  }

  static forbidden(message = "Forbidden", errors: unknown[] = []): ApiError {
    return new ApiError(403, message, errors);
  }

  static notFound(message = "Resource Not Found", errors: unknown[] = []): ApiError {
    return new ApiError(404, message, errors);
  }

  static conflict(message = "Conflict", errors: unknown[] = []): ApiError {
    return new ApiError(409, message, errors);
  }

  static unprocessable(message = "Unprocessable Entity", errors: unknown[] = []): ApiError {
    return new ApiError(422, message, errors);
  }

  static internal(message = "Internal Server Error", errors: unknown[] = []): ApiError {
    return new ApiError(500, message, errors);
  }
}
