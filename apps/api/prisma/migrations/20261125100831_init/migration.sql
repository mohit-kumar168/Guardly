-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateEnum
CREATE TYPE "UserRole" AS ENUM ('PARENT', 'CHILD');

-- CreateEnum
CREATE TYPE "DevicePlatform" AS ENUM ('ANDROID', 'IOS', 'BROWSER');

-- CreateEnum
CREATE TYPE "DeviceStatus" AS ENUM ('PENDING', 'ACTIVE', 'REVOKED');

-- CreateEnum
CREATE TYPE "RuleType" AS ENUM ('APP', 'WEBSITE');

-- CreateEnum
CREATE TYPE "RuleAction" AS ENUM ('ALLOW', 'BLOCK');

-- CreateEnum
CREATE TYPE "OverrideType" AS ENUM ('EXTRA_TIME', 'LOCK_NOW');

-- CreateEnum
CREATE TYPE "ConsentStatus" AS ENUM ('NOT_ASKED', 'PENDING', 'GRANTED', 'DECLINED', 'REVOKED');

-- CreateEnum
CREATE TYPE "ScreenshotSessionStatus" AS ENUM ('SCHEDULED', 'ACTIVE', 'COMPLETED', 'CANCELLED', 'DECLINED', 'UNSUPPORTED');

-- CreateEnum
CREATE TYPE "CaptureStatus" AS ENUM ('PENDING', 'CAPTURED', 'FAILED');

-- CreateEnum
CREATE TYPE "NotificationType" AS ENUM ('DEVICE_PAIRED', 'DEVICE_ONLINE', 'DEVICE_OFFLINE', 'SCREEN_TIME_LIMIT_REACHED', 'BLOCKED_ATTEMPT', 'SCREENSHOT_SESSION_STARTED', 'SCREENSHOT_SESSION_ENDED', 'SCREENSHOT_FAILED', 'PARENT_INVITATION');

-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL,
    "role" "UserRole" NOT NULL,
    "name" TEXT NOT NULL,
    "email" TEXT,
    "passwordHash" TEXT,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "familyId" UUID,
    "lastLoginAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "sessions" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "deviceId" UUID,
    "refreshTokenHash" TEXT NOT NULL,
    "pushToken" TEXT,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "revokedAt" TIMESTAMP(3),
    "lastUsedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "sessions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "families" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "families_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "invitations" (
    "id" UUID NOT NULL,
    "familyId" UUID NOT NULL,
    "email" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "acceptedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "invitations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "devices" (
    "id" UUID NOT NULL,
    "childId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "platform" "DevicePlatform" NOT NULL,
    "osVersion" TEXT,
    "appVersion" TEXT,
    "status" "DeviceStatus" NOT NULL DEFAULT 'PENDING',
    "pairingCodeHash" TEXT,
    "pairingExpiresAt" TIMESTAMP(3),
    "isOnline" BOOLEAN NOT NULL DEFAULT false,
    "lastSeenAt" TIMESTAMP(3),
    "pairedAt" TIMESTAMP(3),
    "revokedAt" TIMESTAMP(3),
    "screenshotsEnabled" BOOLEAN NOT NULL DEFAULT false,
    "canCaptureScreenshots" BOOLEAN NOT NULL DEFAULT false,
    "screenshotConsent" "ConsentStatus" NOT NULL DEFAULT 'NOT_ASKED',
    "screenshotConsentAt" TIMESTAMP(3),
    "disclosureVersion" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "devices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "policies" (
    "id" UUID NOT NULL,
    "familyId" UUID NOT NULL,
    "childId" UUID,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "dailyLimitMinutes" INTEGER,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "policies_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "policy_rules" (
    "id" UUID NOT NULL,
    "policyId" UUID NOT NULL,
    "type" "RuleType" NOT NULL,
    "target" TEXT NOT NULL,
    "label" TEXT,
    "action" "RuleAction" NOT NULL,
    "expiresAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "policy_rules_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "schedules" (
    "id" UUID NOT NULL,
    "policyId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "days" INTEGER[],
    "startTime" TEXT NOT NULL,
    "endTime" TEXT NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "schedules_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "overrides" (
    "id" UUID NOT NULL,
    "childId" UUID NOT NULL,
    "createdById" UUID,
    "type" "OverrideType" NOT NULL,
    "extraMinutes" INTEGER,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "overrides_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "daily_screen_time" (
    "id" UUID NOT NULL,
    "deviceId" UUID NOT NULL,
    "date" DATE NOT NULL,
    "totalSeconds" INTEGER NOT NULL DEFAULT 0,
    "blockedAttempts" INTEGER NOT NULL DEFAULT 0,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "daily_screen_time_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "app_usage" (
    "id" UUID NOT NULL,
    "deviceId" UUID NOT NULL,
    "date" DATE NOT NULL,
    "appId" TEXT NOT NULL,
    "appName" TEXT NOT NULL,
    "seconds" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "app_usage_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "website_usage" (
    "id" UUID NOT NULL,
    "deviceId" UUID NOT NULL,
    "date" DATE NOT NULL,
    "domain" TEXT NOT NULL,
    "visits" INTEGER NOT NULL DEFAULT 0,
    "seconds" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "website_usage_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "screenshot_sessions" (
    "id" UUID NOT NULL,
    "deviceId" UUID NOT NULL,
    "createdById" UUID,
    "intervalMinutes" INTEGER NOT NULL,
    "startsAt" TIMESTAMP(3) NOT NULL,
    "endsAt" TIMESTAMP(3) NOT NULL,
    "status" "ScreenshotSessionStatus" NOT NULL DEFAULT 'SCHEDULED',
    "statusReason" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "screenshot_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "screenshots" (
    "id" UUID NOT NULL,
    "sessionId" UUID NOT NULL,
    "status" "CaptureStatus" NOT NULL DEFAULT 'PENDING',
    "scheduledFor" TIMESTAMP(3) NOT NULL,
    "capturedAt" TIMESTAMP(3),
    "storagePath" TEXT,
    "failureReason" TEXT,
    "viewedAt" TIMESTAMP(3),
    "deleteAfter" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "screenshots_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "notifications" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "type" "NotificationType" NOT NULL,
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "data" JSONB,
    "sentAt" TIMESTAMP(3),
    "readAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "notifications_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "audit_logs" (
    "id" UUID NOT NULL,
    "familyId" UUID,
    "userId" UUID,
    "action" TEXT NOT NULL,
    "targetType" TEXT,
    "targetId" TEXT,
    "details" JSONB,
    "ipAddress" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");

-- CreateIndex
CREATE INDEX "users_familyId_role_idx" ON "users"("familyId", "role");

-- CreateIndex
CREATE UNIQUE INDEX "sessions_refreshTokenHash_key" ON "sessions"("refreshTokenHash");

-- CreateIndex
CREATE INDEX "sessions_userId_idx" ON "sessions"("userId");

-- CreateIndex
CREATE INDEX "sessions_deviceId_idx" ON "sessions"("deviceId");

-- CreateIndex
CREATE UNIQUE INDEX "invitations_tokenHash_key" ON "invitations"("tokenHash");

-- CreateIndex
CREATE INDEX "invitations_familyId_idx" ON "invitations"("familyId");

-- CreateIndex
CREATE INDEX "invitations_email_idx" ON "invitations"("email");

-- CreateIndex
CREATE UNIQUE INDEX "devices_pairingCodeHash_key" ON "devices"("pairingCodeHash");

-- CreateIndex
CREATE INDEX "devices_childId_status_idx" ON "devices"("childId", "status");

-- CreateIndex
CREATE INDEX "devices_status_isOnline_lastSeenAt_idx" ON "devices"("status", "isOnline", "lastSeenAt");

-- CreateIndex
CREATE UNIQUE INDEX "policies_childId_key" ON "policies"("childId");

-- CreateIndex
CREATE INDEX "policies_familyId_idx" ON "policies"("familyId");

-- CreateIndex
CREATE UNIQUE INDEX "policy_rules_policyId_type_target_key" ON "policy_rules"("policyId", "type", "target");

-- CreateIndex
CREATE INDEX "schedules_policyId_idx" ON "schedules"("policyId");

-- CreateIndex
CREATE INDEX "overrides_childId_expiresAt_idx" ON "overrides"("childId", "expiresAt");

-- CreateIndex
CREATE INDEX "overrides_createdById_idx" ON "overrides"("createdById");

-- CreateIndex
CREATE UNIQUE INDEX "daily_screen_time_deviceId_date_key" ON "daily_screen_time"("deviceId", "date");

-- CreateIndex
CREATE UNIQUE INDEX "app_usage_deviceId_date_appId_key" ON "app_usage"("deviceId", "date", "appId");

-- CreateIndex
CREATE UNIQUE INDEX "website_usage_deviceId_date_domain_key" ON "website_usage"("deviceId", "date", "domain");

-- CreateIndex
CREATE INDEX "screenshot_sessions_deviceId_status_idx" ON "screenshot_sessions"("deviceId", "status");

-- CreateIndex
CREATE INDEX "screenshot_sessions_status_startsAt_idx" ON "screenshot_sessions"("status", "startsAt");

-- CreateIndex
CREATE INDEX "screenshot_sessions_createdById_idx" ON "screenshot_sessions"("createdById");

-- CreateIndex
CREATE INDEX "screenshots_sessionId_scheduledFor_idx" ON "screenshots"("sessionId", "scheduledFor");

-- CreateIndex
CREATE INDEX "screenshots_deleteAfter_idx" ON "screenshots"("deleteAfter");

-- CreateIndex
CREATE INDEX "notifications_userId_readAt_createdAt_idx" ON "notifications"("userId", "readAt", "createdAt");

-- CreateIndex
CREATE INDEX "audit_logs_familyId_createdAt_idx" ON "audit_logs"("familyId", "createdAt");

-- CreateIndex
CREATE INDEX "audit_logs_userId_createdAt_idx" ON "audit_logs"("userId", "createdAt");

-- AddForeignKey
ALTER TABLE "users" ADD CONSTRAINT "users_familyId_fkey" FOREIGN KEY ("familyId") REFERENCES "families"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sessions" ADD CONSTRAINT "sessions_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sessions" ADD CONSTRAINT "sessions_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "devices"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "invitations" ADD CONSTRAINT "invitations_familyId_fkey" FOREIGN KEY ("familyId") REFERENCES "families"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "devices" ADD CONSTRAINT "devices_childId_fkey" FOREIGN KEY ("childId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "policies" ADD CONSTRAINT "policies_familyId_fkey" FOREIGN KEY ("familyId") REFERENCES "families"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "policies" ADD CONSTRAINT "policies_childId_fkey" FOREIGN KEY ("childId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "policy_rules" ADD CONSTRAINT "policy_rules_policyId_fkey" FOREIGN KEY ("policyId") REFERENCES "policies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "schedules" ADD CONSTRAINT "schedules_policyId_fkey" FOREIGN KEY ("policyId") REFERENCES "policies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "overrides" ADD CONSTRAINT "overrides_childId_fkey" FOREIGN KEY ("childId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "overrides" ADD CONSTRAINT "overrides_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "daily_screen_time" ADD CONSTRAINT "daily_screen_time_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "devices"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "app_usage" ADD CONSTRAINT "app_usage_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "devices"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "website_usage" ADD CONSTRAINT "website_usage_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "devices"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "screenshot_sessions" ADD CONSTRAINT "screenshot_sessions_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "devices"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "screenshot_sessions" ADD CONSTRAINT "screenshot_sessions_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "screenshots" ADD CONSTRAINT "screenshots_sessionId_fkey" FOREIGN KEY ("sessionId") REFERENCES "screenshot_sessions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "audit_logs" ADD CONSTRAINT "audit_logs_familyId_fkey" FOREIGN KEY ("familyId") REFERENCES "families"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "audit_logs" ADD CONSTRAINT "audit_logs_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

