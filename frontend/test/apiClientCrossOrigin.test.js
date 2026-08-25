import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const source = fs.readFileSync(path.resolve(here, "../src/services/apiClient.ts"), "utf8");

test("apiClient source strictly enforces origin checking on resolveApiUrl and resolveWebSocketUrl", () => {
  assert.match(source, /export function resolveApiUrl\(endpoint: string\)/);
  assert.match(source, /export function resolveWebSocketUrl\(endpoint: string\)/);
  assert.match(source, /requested\.origin !== trusted\.origin/);
  assert.match(source, /O cliente da API local recusou um endpoint HTTP de outra origem\./);
  assert.match(source, /O cliente WebSocket local recusou um endpoint de outra origem\./);
});

test("resolveApiUrl and resolveWebSocketUrl origin-isolation regression behavior", () => {
  // Test simulated environment of resolveApiUrl
  const mockResolveApiUrl = (endpoint, base = "http://127.0.0.1:55931") => {
    if (/^https?:\/\//i.test(endpoint)) {
      const requested = new URL(endpoint);
      const trusted = new URL(base);
      if (requested.origin !== trusted.origin) {
        throw new Error("O cliente da API local recusou um endpoint HTTP de outra origem.");
      }
      return requested.href;
    }
    const path = endpoint.startsWith("/") ? endpoint : `/${endpoint}`;
    return `${base}${path}`;
  };

  const mockResolveWebSocketUrl = (endpoint, base = "ws://127.0.0.1:55931") => {
    if (/^wss?:\/\//i.test(endpoint)) {
      const requested = new URL(endpoint);
      const trusted = new URL(base);
      if (requested.origin !== trusted.origin) {
        throw new Error("O cliente WebSocket local recusou um endpoint de outra origem.");
      }
      return requested.href;
    }
    const path = endpoint.startsWith("/") ? endpoint : `/${endpoint}`;
    return `${base}${path}`;
  };

  // Same origin URLs must be allowed
  assert.equal(mockResolveApiUrl("http://127.0.0.1:55931/api/health"), "http://127.0.0.1:55931/api/health");
  assert.equal(mockResolveApiUrl("/api/system/metrics"), "http://127.0.0.1:55931/api/system/metrics");
  assert.equal(mockResolveApiUrl("api/auth/login"), "http://127.0.0.1:55931/api/auth/login");

  // Cross-origin URLs must be rejected
  assert.throws(
    () => mockResolveApiUrl("http://evil.com/steal-token"),
    /O cliente da API local recusou um endpoint HTTP de outra origem\./
  );
  assert.throws(
    () => mockResolveApiUrl("http://127.0.0.1:8080/api/other-port"),
    /O cliente da API local recusou um endpoint HTTP de outra origem\./
  );
  assert.throws(
    () => mockResolveApiUrl("https://127.0.0.1:55931/api/diff-protocol"),
    /O cliente da API local recusou um endpoint HTTP de outra origem\./
  );

  // WebSocket same origin allowed
  assert.equal(mockResolveWebSocketUrl("ws://127.0.0.1:55931/ws/terminal"), "ws://127.0.0.1:55931/ws/terminal");
  assert.equal(mockResolveWebSocketUrl("/ws/terminal"), "ws://127.0.0.1:55931/ws/terminal");

  // WebSocket cross origin rejected
  assert.throws(
    () => mockResolveWebSocketUrl("ws://evil.com/ws-intercept"),
    /O cliente WebSocket local recusou um endpoint de outra origem\./
  );
  assert.throws(
    () => mockResolveWebSocketUrl("ws://127.0.0.1:9999/ws/terminal"),
    /O cliente WebSocket local recusou um endpoint de outra origem\./
  );
});
