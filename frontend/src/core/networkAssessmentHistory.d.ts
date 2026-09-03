export type NetworkHistoryPort = { port: number; protocol: string; state: string; service: string; version: string };
export type NetworkHistoryHost = { address: string; hostname: string; up: boolean; ports: NetworkHistoryPort[] };
export type NetworkAssessmentHistoryRecord = {
  id: string;
  target: string;
  preset: string;
  label: string;
  distribution: string;
  completedAt: string;
  durationMs: number | null;
  highestSeverity: 'info' | 'low' | 'medium' | 'high' | 'critical';
  hosts: NetworkHistoryHost[];
};
export type NetworkAssessmentDiff = {
  comparable: boolean;
  addedHosts: string[];
  removedHosts: string[];
  changedHosts: Array<{ address: string; openedPorts: string[]; closedPorts: string[]; onlineChanged: boolean; online: boolean }>;
};
export const NETWORK_ASSESSMENT_HISTORY_KEY: string;
export const MAX_NETWORK_ASSESSMENT_HISTORY: number;
export function sanitizeNetworkAssessmentRecord(value: unknown): NetworkAssessmentHistoryRecord | null;
export function normalizeNetworkAssessmentHistory(value: unknown): NetworkAssessmentHistoryRecord[];
export function appendNetworkAssessmentHistory(history: unknown, assessment: unknown): NetworkAssessmentHistoryRecord[];
export function diffNetworkAssessmentRecords(previous: unknown, current: unknown): NetworkAssessmentDiff;
