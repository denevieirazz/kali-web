/**
 * @typedef {Object} UserIdentifier
 * @property {string} [id]
 * @property {string} [userId]
 * @property {string} [role]
 */

let activeScopedUser = null;

export function setActiveScopedUser(user) {
  activeScopedUser = user || null;
}

export function getActiveScopedUser() {
  if (activeScopedUser) return activeScopedUser;
  try {
    const raw = typeof localStorage !== 'undefined' ? localStorage.getItem('cloudos_user') : null;
    if (raw) return JSON.parse(raw);
  } catch {}
  return null;
}

export function isPrimaryUser(user) {
  const target = user !== undefined ? user : getActiveScopedUser();
  if (!target) return true;
  return target.role === 'admin';
}

export function getUserStorageKey(baseKey, user) {
  const target = user !== undefined ? user : getActiveScopedUser();
  if (!target || target.role === 'admin') {
    return baseKey;
  }
  const id = target.id || target.userId;
  if (!id) return baseKey;
  return `${baseKey}.user.${id}`;
}

export function getUserOpfsRootName(user) {
  const target = user !== undefined ? user : getActiveScopedUser();
  if (!target || target.role === 'admin') {
    return 'obsidianos-disk';
  }
  const id = target.id || target.userId;
  if (!id) return 'obsidianos-disk';
  return `obsidianos-disk-user-${id}`;
}

export function switchUserScope(_prevUser, nextUser) {
  setActiveScopedUser(nextUser);
}
