import { resolveCloudFileRef } from '../storage/cloudFileHandoff.js';

const FILE_CAPABLE_WINDOWS_KINDS = new Set([
  'windows-executable',
  'windows-shortcut-direct',
  'windows-shortcut-argv',
]);
const MAX_ARGUMENTS = 128;

function launchError(code, message) {
  return Object.assign(new Error(message), { code });
}

export async function applyCloudFileHandoff(launch, fileRef) {
  if (fileRef === undefined || fileRef === null) return launch;
  if (!launch || typeof launch !== 'object' || !launch.launchSpec || typeof launch.launchSpec !== 'object') {
    throw launchError('APP_LAUNCH_SPEC_INVALID', 'Descritor de lançamento inválido para entrega de arquivo.');
  }
  if (launch.launchKind === 'windows-script-direct') {
    throw launchError('APP_FILE_HANDOFF_UNSUPPORTED', 'Scripts BAT/CMD ainda não aceitam entrega de arquivos pelo broker do CloudOS.');
  }
  if (!FILE_CAPABLE_WINDOWS_KINDS.has(launch.launchKind)) {
    throw launchError('APP_FILE_HANDOFF_UNSUPPORTED', 'Este tipo de aplicativo não aceita entrega de arquivos contida.');
  }

  const resolved = await resolveCloudFileRef(fileRef);
  const currentArguments = Array.isArray(launch.launchSpec.arguments) ? launch.launchSpec.arguments : [];
  if (currentArguments.length >= MAX_ARGUMENTS) {
    throw launchError('APP_ARGUMENT_LIMIT', 'O aplicativo já atingiu o limite seguro de argumentos.');
  }

  return {
    ...launch,
    // A shortcut-direct still starts the exact target executable. Once a file is
    // appended it becomes an explicit argv launch so the Host can validate it.
    launchKind: launch.launchKind === 'windows-shortcut-direct' ? 'windows-shortcut-argv' : launch.launchKind,
    launchSpec: {
      ...launch.launchSpec,
      arguments: [...currentArguments, resolved.absolutePath],
    },
    fileHandoff: {
      provider: resolved.fileRef.provider,
      path: [...resolved.fileRef.path],
    },
  };
}
