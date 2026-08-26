import type { UserProfile } from '../types';

export const ACCOUNT_RECOVERY_ENDPOINT: string;
export function validateUsername(value: unknown): string | null;
export function validateDisplayName(value: unknown): string | null;
export function validateNewPassword(password: unknown, confirmPassword: unknown): string | null;
export function normalizePublicUser(value: unknown, fallback?: { username?: string; displayName?: string }): UserProfile;
export function extractRecoveryCode(value: unknown): string | null;
export function canRestoreAuthenticatedSession(authenticated: unknown, recoveryConfirmationPending: unknown): boolean;
export function sanitizePersistedProfile(value: unknown): UserProfile | null;
export function recoveryRequestBody(value: {
  recoveryCode: string;
  username: string;
  displayName?: string;
  password: string;
  confirmPassword: string;
}): Record<string, unknown>;
