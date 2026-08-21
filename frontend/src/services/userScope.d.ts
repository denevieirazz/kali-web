import type { UserProfile } from '../types';

export interface UserIdentifier {
  id?: string;
  userId?: string;
  role?: string;
}

export function setActiveScopedUser(user: UserProfile | UserIdentifier | null): void;
export function getActiveScopedUser(): (UserProfile & UserIdentifier) | null;
export function isPrimaryUser(user?: UserIdentifier | null): boolean;
export function getUserStorageKey(baseKey: string, user?: UserIdentifier | null): string;
export function getUserOpfsRootName(user?: UserIdentifier | null): string;
export function switchUserScope(prevUser: UserProfile | UserIdentifier | null, nextUser: UserProfile | UserIdentifier | null): void;
