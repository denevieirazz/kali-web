package protocol

import (
	"bytes"
	"encoding/binary"
	"errors"
	"io"
	"testing"
)

type oneByteReader struct{ r io.Reader }

func (r oneByteReader) Read(p []byte) (int, error) {
	if len(p) > 1 {
		p = p[:1]
	}
	return r.r.Read(p)
}

func TestPartialFrameAndVersion(t *testing.T) {
	var buffer bytes.Buffer
	if err := WriteFrame(&buffer, Envelope{Type: "hello", ID: "abc", Payload: Payload(map[string]string{"method": "health"})}); err != nil {
		t.Fatal(err)
	}
	frame, err := ReadFrame(oneByteReader{r: &buffer})
	if err != nil {
		t.Fatal(err)
	}
	if frame.Version != Version || frame.Type != "hello" || frame.ID != "abc" {
		t.Fatalf("unexpected frame: %+v", frame)
	}
}

func TestRejectsOversizeAndInvalidJSON(t *testing.T) {
	var oversized bytes.Buffer
	var header [4]byte
	binary.BigEndian.PutUint32(header[:], MaxFrameBytes+1)
	oversized.Write(header[:])
	if _, err := ReadFrame(&oversized); err != ErrFrameTooLarge {
		t.Fatalf("expected ErrFrameTooLarge, got %v", err)
	}

	var invalid bytes.Buffer
	binary.BigEndian.PutUint32(header[:], 1)
	invalid.Write(header[:])
	invalid.WriteByte('{')
	if _, err := ReadFrame(&invalid); err == nil {
		t.Fatal("invalid JSON accepted")
	}
}

func TestMutualProofIsRoleBound(t *testing.T) {
	secret := bytes.Repeat([]byte{1}, SecretBytes)
	client := bytes.Repeat([]byte{2}, NonceBytes)
	server := bytes.Repeat([]byte{3}, NonceBytes)
	proof := ProofBase64(secret, "server", client, server)
	if !VerifyProof(secret, "server", client, server, proof) {
		t.Fatal("valid proof rejected")
	}
	if VerifyProof(secret, "client", client, server, proof) {
		t.Fatal("server proof accepted as client proof")
	}
	altered := append([]byte(nil), client...)
	altered[0] ^= 0xff
	if VerifyProof(secret, "server", altered, server, proof) {
		t.Fatal("altered nonce accepted")
	}
}

func TestSecureChannelRoundTripAndSequence(t *testing.T) {
	secret := bytes.Repeat([]byte{7}, SecretBytes)
	clientNonce := bytes.Repeat([]byte{8}, NonceBytes)
	serverNonce := bytes.Repeat([]byte{9}, NonceBytes)
	var wire bytes.Buffer
	client, err := NewSecureChannel(bytes.NewReader(nil), &wire, secret, clientNonce, serverNonce, false)
	if err != nil {
		t.Fatal(err)
	}
	if err := client.Write(Envelope{Type: "request", ID: "one", Payload: Payload(map[string]string{"method": "health"})}); err != nil {
		t.Fatal(err)
	}
	captured := append([]byte(nil), wire.Bytes()...)
	server, err := NewSecureChannel(bytes.NewReader(captured), io.Discard, secret, clientNonce, serverNonce, true)
	if err != nil {
		t.Fatal(err)
	}
	frame, err := server.Read()
	if err != nil || frame.Type != "request" || frame.ID != "one" {
		t.Fatalf("protected roundtrip failed: %v %+v", err, frame)
	}

	replay, err := NewSecureChannel(bytes.NewReader(append(captured, captured...)), io.Discard, secret, clientNonce, serverNonce, true)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := replay.Read(); err != nil {
		t.Fatal(err)
	}
	if _, err := replay.Read(); !errors.Is(err, ErrSequence) {
		t.Fatalf("expected replay sequence rejection, got %v", err)
	}
}

func TestSecureChannelRejectsTamperingAndOutOfOrder(t *testing.T) {
	secret := bytes.Repeat([]byte{10}, SecretBytes)
	clientNonce := bytes.Repeat([]byte{11}, NonceBytes)
	serverNonce := bytes.Repeat([]byte{12}, NonceBytes)
	var wire bytes.Buffer
	client, err := NewSecureChannel(bytes.NewReader(nil), &wire, secret, clientNonce, serverNonce, false)
	if err != nil {
		t.Fatal(err)
	}
	if err := client.Write(Envelope{Type: "request", ID: "tamper"}); err != nil {
		t.Fatal(err)
	}
	frame := append([]byte(nil), wire.Bytes()...)
	frame[len(frame)-1] ^= 0x40
	server, _ := NewSecureChannel(bytes.NewReader(frame), io.Discard, secret, clientNonce, serverNonce, true)
	if _, err := server.Read(); !errors.Is(err, ErrIntegrity) {
		t.Fatalf("expected integrity rejection, got %v", err)
	}

	outOfOrder := append([]byte(nil), wire.Bytes()...)
	binary.BigEndian.PutUint64(outOfOrder[4:12], 2)
	server, _ = NewSecureChannel(bytes.NewReader(outOfOrder), io.Discard, secret, clientNonce, serverNonce, true)
	if _, err := server.Read(); !errors.Is(err, ErrSequence) {
		t.Fatalf("expected sequence rejection, got %v", err)
	}
}
