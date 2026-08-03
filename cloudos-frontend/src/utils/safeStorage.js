// =====================================================================
// 🛡️ CloudOS Safe Storage Utility
// Previne erros de Tracking Prevention / Bloqueio de Cookies no Edge/Firefox/Brave
// =====================================================================

const memoryStorage = {};

export const safeGet = (key) => {
  try {
    const val = localStorage.getItem(key);
    return val !== null ? val : memoryStorage[key] || null;
  } catch (e) {
    return memoryStorage[key] || null;
  }
};

export const safeSet = (key, value) => {
  try {
    localStorage.setItem(key, value);
  } catch (e) {
    memoryStorage[key] = String(value);
  }
};

export const safeRemove = (key) => {
  try {
    localStorage.removeItem(key);
  } catch (e) {
    delete memoryStorage[key];
  }
};
