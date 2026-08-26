export type ReadinessContractProfile = 'hybrid-dev' | 'shell-preview' | 'shell-candidate';

export const READINESS_CONTRACT: 'cloudos.readiness/v1';
export const READINESS_SCHEMA_VERSION: 1;
export const REQUIRED_READINESS_CHECK_IDS: Readonly<Record<ReadinessContractProfile, readonly string[]>>;

export interface ReadinessContractValidation {
  valid: boolean;
  errors: string[];
  missingCheckIds: string[];
}

export function validateReadinessContract(
  value: unknown,
  requestedProfile: ReadinessContractProfile
): ReadinessContractValidation;

export interface ReadinessContractFailureCheck {
  id: 'agent.contract';
  group: 'runtime';
  label: string;
  detail: string;
  deliveryState: 'implemented';
  observation: 'fail';
  gating: 'hard';
  source: 'agent';
  evidence: {
    kind: 'contract';
    value: {
      expected: typeof READINESS_CONTRACT;
      errors: string[];
      missingCheckIds: string[];
    };
    code: 'READINESS_CONTRACT_INVALID';
    observedAt: string;
  };
  blocking: true;
}

export function createReadinessContractFailure(
  validation: ReadinessContractValidation,
  observedAt: string
): ReadinessContractFailureCheck;

export function fullscreenReadinessObservation(
  profile: ReadinessContractProfile,
  fullscreen: boolean
): 'pass' | 'warning' | 'fail';
