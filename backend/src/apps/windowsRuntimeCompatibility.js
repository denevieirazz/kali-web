export const WINDOWS_RUNTIME_STATUS = Object.freeze({
  UNQUALIFIED: 'UNQUALIFIED',
  CAPTURE_SUPPORTED: 'CAPTURE_SUPPORTED',
  CAPTURE_BLOCKED: 'CAPTURE_BLOCKED',
  BROKER_UNSAFE: 'BROKER_UNSAFE',
  SINGLETON_UNSAFE: 'SINGLETON_UNSAFE',
  RENDER_FAILED: 'RENDER_FAILED',
  INPUT_UNSUPPORTED: 'INPUT_UNSUPPORTED'
});

const PERSISTABLE_QUALIFICATION = new Set([
  WINDOWS_RUNTIME_STATUS.CAPTURE_SUPPORTED,
  WINDOWS_RUNTIME_STATUS.CAPTURE_BLOCKED,
  WINDOWS_RUNTIME_STATUS.BROKER_UNSAFE,
  WINDOWS_RUNTIME_STATUS.SINGLETON_UNSAFE,
  WINDOWS_RUNTIME_STATUS.RENDER_FAILED,
  WINDOWS_RUNTIME_STATUS.INPUT_UNSUPPORTED
]);

export function classifyCatalogRuntime(app, qualification = null) {
  if (!app || app.source !== 'windows') return null;

  if (qualification && PERSISTABLE_QUALIFICATION.has(qualification.status)) {
    return {
      status: qualification.status,
      reason: String(qualification.reason || '').slice(0, 512) || null,
      qualifiedAt: qualification.qualifiedAt || null,
      evidenceRevision: qualification.evidenceRevision || null
    };
  }

  if (app.runtimeClass === 'brokered-start-app' || app.kind === 'windows-start-app') {
    return {
      status: WINDOWS_RUNTIME_STATUS.BROKER_UNSAFE,
      reason: 'Start-app/UWP/protocol targets are brokered and cannot satisfy direct PID/Job correlation.',
      qualifiedAt: null,
      evidenceRevision: null
    };
  }

  if (app.runtimeClass === 'win32-shortcut-unresolved' || app.kind === 'windows-shortcut') {
    return {
      status: WINDOWS_RUNTIME_STATUS.CAPTURE_BLOCKED,
      reason: 'Shortcut arguments could not be converted into a bounded direct argv launch specification.',
      qualifiedAt: null,
      evidenceRevision: null
    };
  }

  return {
    status: WINDOWS_RUNTIME_STATUS.UNQUALIFIED,
    reason: 'Direct launch candidate has not passed physical captured-surface qualification yet.',
    qualifiedAt: null,
    evidenceRevision: null
  };
}

export function validateRuntimeQualification(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  if (!PERSISTABLE_QUALIFICATION.has(value.status)) return null;
  if (typeof value.reason !== 'string' || !value.reason.trim() || value.reason.length > 512) return null;
  if (value.qualifiedAt !== undefined && value.qualifiedAt !== null && typeof value.qualifiedAt !== 'string') return null;
  if (value.evidenceRevision !== undefined && value.evidenceRevision !== null && typeof value.evidenceRevision !== 'string') return null;
  return {
    status: value.status,
    reason: value.reason.trim(),
    qualifiedAt: value.qualifiedAt || null,
    evidenceRevision: value.evidenceRevision || null
  };
}
