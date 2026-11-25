import bcrypt from "bcrypt";
import { env } from "../config/env";
import { ApiError } from "./apiError";

/**
 * Hash a plain text password using bcrypt.
 *
 * @param password - Plain text password to hash
 * @param saltRounds - Number of hashing rounds (defaults to env.BCRYPT_SALT_ROUNDS or 10)
 * @returns Hashed password string
 */
export async function hashPassword(
  password: string,
  saltRounds: number = env.BCRYPT_SALT_ROUNDS
): Promise<string> {
  if (!password || typeof password !== "string") {
    throw ApiError.badRequest("Password must be a non-empty string");
  }

  return bcrypt.hash(password, saltRounds);
}

/**
 * Verify a plain text password against a stored bcrypt hash.
 *
 * @param password - Plain text password to verify
 * @param hash - Stored bcrypt password hash
 * @returns True if password matches hash, false otherwise
 */
export async function verifyPassword(
  password: string,
  hash: string | null | undefined
): Promise<boolean> {
  if (!password || !hash) {
    return false;
  }

  try {
    return await bcrypt.compare(password, hash);
  } catch {
    return false;
  }
}
