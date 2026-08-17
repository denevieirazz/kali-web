import { execFileSync } from 'node:child_process';

const BASE = 'be36ba9d01f207f56b03c9f5e824e500b83b8e22';
const allowed = [
  /^WORKFLOW_AUDIT\.md$/,
  /^WORKFLOW_PRODUCTIVITY_REVIEW\.md$/,
  /^\.github\/workflows\/workflow-batch3-ci\.yml$/,
  /^scripts\/workflow\/test-batch3-scope\.mjs$/,
  /^scripts\/launch\/start-cloudos\.ps1$/,
  /^frontend\/test\/workflow(?:Core|Contract)\.test\.js$/,
  /^frontend\/test\/terminalWorkspaceState\.test\.js$/,
  /^frontend\/test\/rcLauncherDefect001\.test\.js$/,
  /^frontend\/src\/core\/workflowCore\.(?:js|d\.ts)$/,
  /^frontend\/src\/services\/workflow(?:Workspace|WorkspaceTransfer|RecentFiles|Clipboard|Launch|Window)\.ts$/,
  /^frontend\/src\/apps\/WorkflowWorkspace\//,
  /^frontend\/src\/components\/Workflow\//,
  /^frontend\/src\/App\.tsx$/,
  /^frontend\/src\/core\/appRegistry\.ts$/,
  /^frontend\/src\/core\/fs\/apps\.ts$/,
  /^frontend\/src\/components\/Window\/Window\.tsx$/,
  /^frontend\/src\/core\/terminalWorkspaceState\.(?:js|d\.ts)$/,
  /^frontend\/src\/apps\/CloudOSTerminal\/(?:CloudOSTerminal|TerminalSession)\.tsx$/,
  /^frontend\/src\/apps\/CloudOSFiles\/(?:CloudOSFiles|fileSourceFacade|windowsDirectorySource|wslFileSource)\.tsx?$/,
  /^frontend\/src\/apps\/CloudOSFiles\/(?:FilePreviewPanel\.tsx|CloudOSFilesPreview\.css)$/,
];

const output = execFileSync('git', ['diff', '--name-only', `${BASE}...HEAD`], { encoding: 'utf8' });
const changed = output.split(/\r?\n/).map(value => value.trim()).filter(Boolean);
const rejected = changed.filter(path => !allowed.some(pattern => pattern.test(path)));

if (rejected.length) {
  console.error('WORKFLOW_BATCH3_SCOPE_FAILED');
  for (const path of rejected) console.error(`protected-or-unexpected=${path}`);
  process.exit(1);
}

const frozenPatterns = [
  /^desktop\//,
  /^scripts\/productization\//,
  /^frontend\/src\/apps\/Browser\//,
  /^backend\/src\/terminal\/wslCoreAdapter\.js$/,
  /^backend\/src\/terminal\/websocket\.js$/,
];
const frozenTouched = changed.filter(path => frozenPatterns.some(pattern => pattern.test(path)));
if (frozenTouched.length) {
  console.error('WORKFLOW_BATCH3_FROZEN_SCOPE_FAILED');
  for (const path of frozenTouched) console.error(`frozen=${path}`);
  process.exit(1);
}

console.log(`WORKFLOW_BATCH3_SCOPE_OK base=${BASE} changed=${changed.length}`);
