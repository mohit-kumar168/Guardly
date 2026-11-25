import type { Request, Response, NextFunction } from "express";
import { prisma } from "../db/prisma";
import { verifyAccessToken } from "../utils/jwt";

export interface AuthenticatedUser {
  id: string;
  name: string;
  email: string | null;
  role: string;
  familyId: string | null;
}

export interface AuthenticatedSession {
  id: string;
}

declare global {
  namespace Express {
    interface Request {
      user?: AuthenticatedUser;
      session?: AuthenticatedSession;
    }
  }
}

function getAccessToken(req: Request): string | undefined {
  const cookieToken = req.cookies?.accessToken;

  if (cookieToken) {
    return cookieToken;
  }

  const authHeader = req.headers.authorization;

  if (authHeader?.startsWith("Bearer ")) {
    return authHeader.split(" ")[1];
  }

  return undefined;
}

export async function authenticate(
  req: Request,
  res: Response,
  next: NextFunction,
) {
  try {
    const token = getAccessToken(req);

    if (!token) {
      return res.status(401).json({
        success: false,
        message: "Authentication required",
      });
    }

    const payload = verifyAccessToken(token);

    const session = await prisma.session.findFirst({
      where: {
        id: payload.sessionId,
        userId: payload.userId,
        revokedAt: null,
        expiresAt: { gt: new Date() },
      },
      select: {
        id: true,
        user: {
          select: {
            id: true,
            name: true,
            email: true,
            role: true,
            familyId: true,
            isActive: true,
          },
        },
      },
    });

    if (!session || !session.user.isActive) {
      return res.status(401).json({
        success: false,
        message: "Session expired or invalid",
      });
    }

    req.user = {
      id: session.user.id,
      name: session.user.name,
      email: session.user.email,
      role: session.user.role,
      familyId: session.user.familyId,
    };

    req.session = {
      id: session.id,
    };

    next();
  } catch (error) {
    if (
      error instanceof Error &&
      (error.name === "JsonWebTokenError" ||
        error.name === "TokenExpiredError" ||
        error.name === "NotBeforeError")
    ) {
      return res.status(401).json({
        success: false,
        message: "Invalid or expired access token",
      });
    }

    next(error);
  }
}

export function optionalAuthenticate(
  req: Request,
  res: Response,
  next: NextFunction,
) {
  const token = getAccessToken(req);

  if (!token) {
    return next();
  }

  let payload;

  try {
    payload = verifyAccessToken(token);
  } catch {
    return next();
  }

  // Database errors are passed to the global error handler.
  prisma.session
    .findFirst({
      where: {
        id: payload.sessionId,
        userId: payload.userId,
        revokedAt: null,
        expiresAt: { gt: new Date() },
      },
      select: {
        id: true,
        user: {
          select: {
            id: true,
            name: true,
            email: true,
            role: true,
            familyId: true,
            isActive: true,
          },
        },
      },
    })
    .then((session) => {
      if (session?.user.isActive) {
        req.user = {
          id: session.user.id,
          name: session.user.name,
          email: session.user.email,
          role: session.user.role,
          familyId: session.user.familyId,
        };

        req.session = { id: session.id };
      }

      next();
    })
    .catch(next);
}

export function requireRole(...roles: string[]) {
  return (req: Request, res: Response, next: NextFunction) => {
    if (!req.user) {
      return res.status(401).json({
        success: false,
        message: "Authentication required",
      });
    }

    if (!roles.includes(req.user.role)) {
      return res.status(403).json({
        success: false,
        message: "You do not have permission to access this resource",
      });
    }

    next();
  };
}

