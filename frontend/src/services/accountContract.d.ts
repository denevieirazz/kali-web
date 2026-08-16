import type { UserProfile } from '../types';

export const ACCOUNT_RECOVERY_ENDPOINT: string;
export const ACCOUNT_LEGACY_RECOVERY_ENDPOINT: string;
export const MIN_PASSWORD_LENGTH: number;
export const MAX_PASSWORD_LENGTH: number;
export function validateUsername(value: unknown, options?: { required?: boolean }): string | null;
export function validateDisplayName(value: unknown, options?: { required?: boolean }): string | null;
export function validateNewPassword(password: unknown, confirmPassword: unknown): string | null;
export function normalizeReadableRecoveryCode(value: unknown): string;
export function extractRecoveryCodeFromText(value: unknown): string;
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
export function legacyRecoveryRequestBody(value: {
  legacyToken: string;
  username: string;
  displayName?: string;
  password: string;
  confirmPassword: string;
}): Record<string, unknown>;
