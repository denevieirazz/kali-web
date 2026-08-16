package protocol

import (
	"bytes"
	"encoding/binary"
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
	if err := WriteFrame(&buffer, Envelope{Type: "request", ID: "abc", Payload: Payload(map[string]string{"method": "health"})}); err != nil {
		t.Fatal(err)
	}
	frame, err := ReadFrame(oneByteReader{r: &buffer})
	if err != nil {
		t.Fatal(err)
	}
	if frame.Version != Version || frame.Type != "request" || frame.ID != "abc" {
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
