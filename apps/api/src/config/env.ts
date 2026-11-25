import "dotenv/config";

export const env = {
  NODE_ENV: process.env.NODE_ENV ?? "development",
  PORT: Number(process.env.PORT) || 8000,
  DATABASE_URL: process.env.DATABASE_URL!,
  JWT_ACCESS_SECRET:
    process.env.JWT_ACCESS_SECRET || "guardly_default_access_secret_key_change_in_prod",
  JWT_ACCESS_EXPIRES_IN: process.env.JWT_ACCESS_EXPIRES_IN || "15m",
  JWT_REFRESH_SECRET:
    process.env.JWT_REFRESH_SECRET || "guardly_default_refresh_secret_key_change_in_prod",
  JWT_REFRESH_EXPIRES_IN: process.env.JWT_REFRESH_EXPIRES_IN || "7d",
  BCRYPT_SALT_ROUNDS: Number(process.env.BCRYPT_SALT_ROUNDS) || 10,
};
