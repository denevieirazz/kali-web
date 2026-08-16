import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { checkUpdate, compareSemver, parseSemver, sanitizeProductStatus, validateUpdateSource } from '../src/product/routes.js';

test('product status exposes only bounded product diagnostics', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cloudos-product-status-'));
  try {
    fs.mkdirSync(path.join(root, 'meta'), { recursive: true });
    fs.writeFileSync(path.join(root, 'meta', 'product.json'), JSON.stringify({schemaVersion:1,product:'CloudOS',version:'1.1.0-batch2.1',channel:'development',baseSha:'a'.repeat(40),signing:'unsigned-development',stableUpdatesEnabled:false}));
    const status = sanitizeProductStatus({ ...process.env, CLOUDOS_LOCAL_ROOT:path.join(root,'local'), CLOUDOS_NATIVE_HOST:'1', CLOUDOS_UPDATE_SOURCE:'https://updates.example.test/cloudos' }, root);
    assert.equal(status.version, '1.1.0-batch2.1');
    assert.equal(status.mode, 'Full');
    assert.equal(status.nativeHost, true);
    assert.equal(status.updateConfigured, true);
    assert.equal(status.signing, 'unsigned-development');
    assert.equal('updateSource' in status, false);
  } finally { fs.rmSync(root,{recursive:true,force:true}); }
});

test('semver comparison handles CloudOS prerelease sequence without allowing silent downgrade', () => {
  assert.ok(compareSemver(parseSemver('1.1.0-batch2.2'), parseSemver('1.1.0-batch2.1')) > 0);
  assert.ok(compareSemver(parseSemver('1.1.0'), parseSemver('1.1.0-batch2.9')) > 0);
  assert.ok(compareSemver(parseSemver('1.0.9'), parseSemver('1.1.0-batch2.1')) < 0);
});

test('update source accepts HTTPS and explicit development loopback only', () => {
  assert.equal(validateUpdateSource('https://example.test/cloudos','preview',{}).kind,'https');
  assert.throws(()=>validateUpdateSource('http://example.test/cloudos','development',{CLOUDOS_ALLOW_LOCAL_UPDATE_FIXTURE:'1'}));
  assert.equal(validateUpdateSource('http://127.0.0.1:9898/cloudos','development',{CLOUDOS_ALLOW_LOCAL_UPDATE_FIXTURE:'1'}).kind,'http-loopback');
});

test('local update fixture finds newer full release with SHA-256 and rejects downgrade', async () => {
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'cloudos-update-feed-'));
  try{
    fs.mkdirSync(path.join(root,'meta'),{recursive:true});
    fs.writeFileSync(path.join(root,'meta','product.json'),JSON.stringify({schemaVersion:1,product:'CloudOS',version:'1.1.0-batch2.1',channel:'development',stableUpdatesEnabled:false}));
    const feed=path.join(root,'feed');fs.mkdirSync(feed);
    fs.writeFileSync(path.join(feed,'releases.development.json'),JSON.stringify({Assets:[
      {PackageId:'CloudOS.Experimental',Version:'1.1.0-batch2.2',Type:'Full',FileName:'next.nupkg',SHA256:'b'.repeat(64),Size:1234},
      {PackageId:'CloudOS.Experimental',Version:'1.0.0',Type:'Full',FileName:'old.nupkg',SHA256:'c'.repeat(64),Size:800}
    ]}));
    const result=await checkUpdate({CLOUDOS_UPDATE_SOURCE:feed},root,new AbortController().signal);
    assert.equal(result.state,'available');assert.equal(result.latestVersion,'1.1.0-batch2.2');
  }finally{fs.rmSync(root,{recursive:true,force:true})}
});
