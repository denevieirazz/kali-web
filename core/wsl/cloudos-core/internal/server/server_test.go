package server

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net"
	"syscall"
	"testing"
	"time"

	"github.com/denevieirazz/kali-web/core/wsl/cloudos-core/internal/protocol"
)

func TestBootstrapSecretValidation(t *testing.T) {
	valid := bytes.Repeat([]byte{7}, protocol.SecretBytes)
	encoded := base64.StdEncoding.EncodeToString(valid) + "\n"
	decoded, err := readSecret(bytes.NewBufferString(encoded))
	if err != nil || !EqualSecret(valid, decoded) {
		t.Fatalf("valid secret rejected: %v", err)
	}
	if _, err := readSecret(bytes.NewBufferString("not-base64\n")); err == nil {
		t.Fatal("invalid secret accepted")
	}
}

func TestAuthenticationProducesProtectedReady(t *testing.T) {
	secret := bytes.Repeat([]byte{9}, protocol.SecretBytes)
	serverSide, clientSide := net.Pipe()
	defer serverSide.Close()
	defer clientSide.Close()
	srv := &Server{secret: secret, distro: DistroInfo{ID: "test"}}
	result := make(chan error, 1)
	go func() {
		owner, _, err := srv.authenticate(serverSide)
		if err == nil && owner == "" {
			err = bytes.ErrTooLarge
		}
		result <- err
	}()
	secure := authenticateTestClient(t, clientSide, secret)
	if secure == nil {
		t.Fatal("secure channel missing")
	}
	select {
	case err := <-result:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("authentication timed out")
	}
}

func TestWrongAuthenticationProofFails(t *testing.T) {
	secret := bytes.Repeat([]byte{1}, protocol.SecretBytes)
	serverSide, clientSide := net.Pipe()
	defer serverSide.Close()
	defer clientSide.Close()
	srv := &Server{secret: secret}
	result := make(chan error, 1)
	go func() { _, _, err := srv.authenticate(serverSide); result <- err }()
	nonce := bytes.Repeat([]byte{2}, protocol.NonceBytes)
	_ = protocol.WriteFrame(clientSide, protocol.Envelope{Type: "hello", Payload: protocol.Payload(map[string]string{"clientNonce": base64.StdEncoding.EncodeToString(nonce)})})
	if _, err := protocol.ReadFrame(clientSide); err != nil {
		t.Fatal(err)
	}
	_ = protocol.WriteFrame(clientSide, protocol.Envelope{Type: "proof", Payload: protocol.Payload(map[string]string{"proof": base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{0}, 32))})})
	select {
	case err := <-result:
		if err == nil {
			t.Fatal("bad proof accepted")
		}
	case <-time.After(time.Second):
		t.Fatal("auth failure timed out")
	}
}

func authenticateTestClient(t *testing.T, conn net.Conn, secret []byte) *protocol.SecureChannel {
	t.Helper()
	clientNonce := bytes.Repeat([]byte{5}, protocol.NonceBytes)
	if err := protocol.WriteFrame(conn, protocol.Envelope{Type: "hello", Payload: protocol.Payload(map[string]string{"clientNonce": base64.StdEncoding.EncodeToString(clientNonce)})}); err != nil {
		t.Fatal(err)
	}
	challenge, err := protocol.ReadFrame(conn)
	if err != nil {
		t.Fatal(err)
	}
	var body struct {
		ServerNonce string `json:"serverNonce"`
		Proof       string `json:"proof"`
	}
	if err := json.Unmarshal(challenge.Payload, &body); err != nil {
		t.Fatal(err)
	}
	serverNonce, err := base64.StdEncoding.DecodeString(body.ServerNonce)
	if err != nil || !protocol.VerifyProof(secret, "server", clientNonce, serverNonce, body.Proof) {
		t.Fatal("server authentication proof failed")
	}
	clientProof := protocol.ProofBase64(secret, "client", clientNonce, serverNonce)
	if err := protocol.WriteFrame(conn, protocol.Envelope{Type: "proof", Payload: protocol.Payload(map[string]string{"proof": clientProof})}); err != nil {
		t.Fatal(err)
	}
	secure, err := protocol.NewSecureChannel(conn, conn, secret, clientNonce, serverNonce, false)
	if err != nil {
		t.Fatal(err)
	}
	ready, err := secure.Read()
	if err != nil || ready.Type != "ready" {
		t.Fatalf("protected ready failed: %v", err)
	}
	var readyBody struct {
		Protocol   int    `json:"protocol"`
		Protection string `json:"protection"`
	}
	if json.Unmarshal(ready.Payload, &readyBody) != nil || readyBody.Protocol != protocol.Version || readyBody.Protection != "aes-256-gcm-seq" {
		t.Fatalf("protected ready payload invalid: %+v", readyBody)
	}
	return secure
}

func requestTest(t *testing.T, secure *protocol.SecureChannel, id, method string, params any) protocol.Envelope {
	t.Helper()
	if err := secure.Write(protocol.Envelope{Type: "request", ID: id, Payload: protocol.Payload(map[string]any{"method": method, "params": params})}); err != nil {
		t.Fatal(err)
	}
	for {
		response, err := secure.Read()
		if err != nil {
			t.Fatal(err)
		}
		if response.Type == "response" && response.ID == id {
			return response
		}
	}
}

func TestServeConnectionHealthAndShutdown(t *testing.T) {
	secret := bytes.Repeat([]byte{8}, protocol.SecretBytes)
	serverSide, clientSide := net.Pipe()
	srv := &Server{secret: secret, distro: DistroInfo{ID: "test"}}
	result := make(chan error, 1)
	go func() { result <- srv.serveConnection(serverSide, io.Discard) }()
	secure := authenticateTestClient(t, clientSide, secret)
	health := requestTest(t, secure, "health-1", "health", nil)
	if health.OK == nil || !*health.OK {
		t.Fatalf("health failed: %+v", health.Error)
	}
	var healthBody struct {
		Protocol   int    `json:"protocol"`
		Protection string `json:"protection"`
	}
	if json.Unmarshal(health.Payload, &healthBody) != nil || healthBody.Protocol != protocol.Version || healthBody.Protection != "aes-256-gcm-seq" {
		t.Fatalf("health did not prove protected v2: %+v", healthBody)
	}
	shutdown := requestTest(t, secure, "shutdown-1", "shutdown", nil)
	if shutdown.OK == nil || !*shutdown.OK {
		t.Fatalf("shutdown failed: %+v", shutdown.Error)
	}
	_ = clientSide.Close()
	select {
	case err := <-result:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("shutdown did not stop connection")
	}
}

func TestTerminalCreateIsFixedAndSinglePerConnection(t *testing.T) {
	secret := bytes.Repeat([]byte{4}, protocol.SecretBytes)
	serverSide, clientSide := net.Pipe()
	srv := &Server{secret: secret, distro: DistroInfo{ID: "test"}}
	result := make(chan error, 1)
	go func() { result <- srv.serveConnection(serverSide, io.Discard) }()
	secure := authenticateTestClient(t, clientSide, secret)
	created := requestTest(t, secure, "terminal-1", "terminal.create", map[string]int{"rows": 24, "cols": 80})
	if created.OK == nil || !*created.OK {
		t.Fatalf("terminal create failed: %+v", created.Error)
	}
	var status struct {
		SessionID string `json:"sessionId"`
		PID       int    `json:"pid"`
		PTY       bool   `json:"pty"`
	}
	if json.Unmarshal(created.Payload, &status) != nil || status.SessionID == "" || status.PID <= 0 || !status.PTY {
		t.Fatalf("invalid terminal status: %+v", status)
	}
	second := requestTest(t, secure, "terminal-2", "terminal.create", map[string]int{"rows": 24, "cols": 80})
	if second.OK == nil || *second.OK || second.Error == nil || second.Error.Code != "TERMINAL_SESSION_LIMIT" {
		t.Fatalf("second terminal was not rejected: %+v", second)
	}
	_ = requestTest(t, secure, "terminal-signal", "session.signal", map[string]string{"sessionId": status.SessionID, "signal": "terminate"})
	_ = requestTest(t, secure, "shutdown", "shutdown", nil)
	_ = clientSide.Close()
	select {
	case <-result:
	case <-time.After(3 * time.Second):
		t.Fatal("terminal shutdown timed out")
	}
}

func TestDisconnectCleansOwnedProcess(t *testing.T) {
	secret := bytes.Repeat([]byte{6}, protocol.SecretBytes)
	serverSide, clientSide := net.Pipe()
	srv := &Server{secret: secret, distro: DistroInfo{ID: "test"}}
	result := make(chan error, 1)
	go func() { result <- srv.serveConnection(serverSide, io.Discard) }()
	secure := authenticateTestClient(t, clientSide, secret)
	created := requestTest(t, secure, "create-1", "session.create", map[string]any{"executable": "/bin/sleep", "args": []string{"30"}})
	if created.OK == nil || !*created.OK {
		t.Fatalf("create failed: %+v", created.Error)
	}
	var status struct {
		PID int `json:"pid"`
	}
	if err := json.Unmarshal(created.Payload, &status); err != nil || status.PID <= 0 {
		t.Fatalf("invalid session status: %v pid=%d", err, status.PID)
	}
	_ = clientSide.Close()
	select {
	case <-result:
	case <-time.After(4 * time.Second):
		t.Fatal("server did not return after disconnect")
	}
	for i := 0; i < 40; i++ {
		err := syscall.Kill(status.PID, 0)
		if errors.Is(err, syscall.ESRCH) {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	_ = syscall.Kill(status.PID, syscall.SIGKILL)
	t.Fatalf("process %d survived disconnect cleanup", status.PID)
}
