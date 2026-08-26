import { apiClient } from './apiClient';
import type { CloudFileRef } from './cloudFileRef';

interface NativeFileHandoffResponse {
  launchAppId: string;
  expiresAt: number;
}

export async function stageNativeFileLaunch(appId: string, fileRef: CloudFileRef) {
  const result = await apiClient<NativeFileHandoffResponse>(`/api/apps/${encodeURIComponent(appId)}/file-handoff`, {
    method: 'POST',
    body: JSON.stringify({ fileRef }),
    timeoutMs: 15_000,
  });
  if (!/^native-[a-f0-9]{24}$/.test(result.launchAppId) || !Number.isFinite(result.expiresAt)) {
    throw new Error('O broker de arquivos retornou uma capability nativa inválida.');
  }
  return result;
}
