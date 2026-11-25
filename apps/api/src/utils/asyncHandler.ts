import type { Request, Response, NextFunction, RequestHandler } from "express";

export type AsyncRequestHandler<
  P = Record<string, string>,
  ResBody = unknown,
  ReqBody = unknown,
  ReqQuery = qs.ParsedQs,
  Locals extends Record<string, unknown> = Record<string, unknown>
> = (
  req: Request<P, ResBody, ReqBody, ReqQuery, Locals>,
  res: Response<ResBody, Locals>,
  next: NextFunction
) => Promise<unknown> | unknown;

/**
 * Wraps async Express handlers/middlewares to catch and forward unhandled rejections to next().
 * Returns the underlying Promise so it can be awaited in tests and middleware chains.
 */
export const asyncHandler = <
  P = Record<string, string>,
  ResBody = unknown,
  ReqBody = unknown,
  ReqQuery = qs.ParsedQs,
  Locals extends Record<string, unknown> = Record<string, unknown>
>(
  fn: AsyncRequestHandler<P, ResBody, ReqBody, ReqQuery, Locals>
): RequestHandler<P, ResBody, ReqBody, ReqQuery, Locals> => {
  return (req, res, next) => {
    return Promise.resolve(fn(req, res, next)).catch(next) as any;
  };
};
