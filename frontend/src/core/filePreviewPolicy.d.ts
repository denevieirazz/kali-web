export type PreviewKind = 'text' | 'image' | 'pdf' | 'audio' | 'video' | 'unsupported';
export const PREVIEW_LIMITS: Readonly<Record<'text' | 'image' | 'pdf' | 'audio' | 'video', number>>;
export function fileExtension(name: unknown): string;
export function classifyPreview(input?: { name?: string; type?: string; size?: number }): {
  kind: PreviewKind;
  allowed: boolean;
  limit: number;
  reason: string;
};
