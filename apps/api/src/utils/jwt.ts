import jwt, { type SignOptions } from "jsonwebtoken";
import { env } from "../config/env";

export interface TokenUserPayload {
  userId: string;
  sessionId: string;
  role: string;
}

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
}

const accessOptions: SignOptions = {
  algorithm: "HS256",
  expiresIn: env.JWT_ACCESS_EXPIRES_IN as SignOptions["expiresIn"],
};

const refreshOptions: SignOptions = {
  algorithm: "HS256",
  expiresIn: env.JWT_REFRESH_EXPIRES_IN as SignOptions["expiresIn"],
};

export function signAccessToken(payload: TokenUserPayload): string {
  return jwt.sign(payload, env.JWT_ACCESS_SECRET, accessOptions);
}

export function signRefreshToken(payload: TokenUserPayload): string {
  return jwt.sign(payload, env.JWT_REFRESH_SECRET, refreshOptions);
}

export function verifyAccessToken(token: string): TokenUserPayload {
  const payload = jwt.verify(token, env.JWT_ACCESS_SECRET, {
    algorithms: ["HS256"],
  });

  if (
    typeof payload === "string" ||
    typeof payload.userId !== "string" ||
    typeof payload.sessionId !== "string" ||
    typeof payload.role !== "string"
  ) {
    throw new Error("Invalid access token");
  }

  return payload as TokenUserPayload;
}

export function verifyRefreshToken(token: string): TokenUserPayload {
  const payload = jwt.verify(token, env.JWT_REFRESH_SECRET, {
    algorithms: ["HS256"],
  });

  if (
    typeof payload === "string" ||
    typeof payload.userId !== "string" ||
    typeof payload.sessionId !== "string" ||
    typeof payload.role !== "string"
  ) {
    throw new Error("Invalid refresh token");
  }

  return payload as TokenUserPayload;
}

export function generateAuthTokens(
  payload: TokenUserPayload,
): AuthTokens {
  return {
    accessToken: signAccessToken(payload),
    refreshToken: signRefreshToken(payload),
  };
}

