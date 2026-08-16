package server

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"net"
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

func TestAuthenticationVersionAndProof(t *testing.T) {
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
	clientNonce := bytes.Repeat([]byte{4}, protocol.NonceBytes)
	if err := protocol.WriteFrame(clientSide, protocol.Envelope{Type: "hello", Payload: protocol.Payload(map[string]string{"clientNonce": base64.StdEncoding.EncodeToString(clientNonce)})}); err != nil {
		t.Fatal(err)
	}
	challenge, err := protocol.ReadFrame(clientSide)
	if err != nil {
		t.Fatal(err)
	}
	var body struct {
		ServerNonce string `json:"serverNonce"`
		Proof       string `json:"proof"`
	}
	if json.Unmarshal(challenge.Payload, &body) != nil {
		t.Fatal("challenge invalid")
	}
	serverNonce, _ := base64.StdEncoding.DecodeString(body.ServerNonce)
	if !protocol.VerifyProof(secret, "server", clientNonce, serverNonce, body.Proof) {
		t.Fatal("server proof invalid")
	}
	proof := protocol.ProofBase64(secret, "client", clientNonce, serverNonce)
	if err := protocol.WriteFrame(clientSide, protocol.Envelope{Type: "proof", Payload: protocol.Payload(map[string]string{"proof": proof})}); err != nil {
		t.Fatal(err)
	}
	ready, err := protocol.ReadFrame(clientSide)
	if err != nil || ready.Type != "ready" {
		t.Fatalf("ready failed: %v %+v", err, ready)
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
	challenge, err := protocol.ReadFrame(clientSide)
	if err != nil {
		t.Fatal(err)
	}
	var body map[string]string
	_ = json.Unmarshal(challenge.Payload, &body)
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
