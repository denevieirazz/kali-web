package protocol

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"sync"
)

const (
	Version       = 1
	MaxFrameBytes = 1 << 20
	MaxIOBytes    = 64 << 10
	NonceBytes    = 32
	SecretBytes   = 32
)

var (
	ErrFrameTooLarge = errors.New("frame exceeds protocol limit")
	ErrFrameEmpty    = errors.New("empty frame")
	ErrVersion       = errors.New("unsupported protocol version")
)

type ErrorBody struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type Envelope struct {
	Version int             `json:"v"`
	Type    string          `json:"type"`
	ID      string          `json:"id,omitempty"`
	OK      *bool           `json:"ok,omitempty"`
	Payload json.RawMessage `json:"payload,omitempty"`
	Error   *ErrorBody      `json:"error,omitempty"`
}

type Writer struct {
	mu sync.Mutex
	w  io.Writer
}

func NewWriter(w io.Writer) *Writer { return &Writer{w: w} }

func (w *Writer) Write(env Envelope) error {
	w.mu.Lock()
	defer w.mu.Unlock()
	return WriteFrame(w.w, env)
}

func WriteFrame(w io.Writer, env Envelope) error {
	if env.Version == 0 {
		env.Version = Version
	}
	body, err := json.Marshal(env)
	if err != nil {
		return err
	}
	if len(body) == 0 {
		return ErrFrameEmpty
	}
	if len(body) > MaxFrameBytes {
		return ErrFrameTooLarge
	}
	var header [4]byte
	binary.BigEndian.PutUint32(header[:], uint32(len(body)))
	if _, err := w.Write(header[:]); err != nil {
		return err
	}
	_, err = w.Write(body)
	return err
}

func ReadFrame(r io.Reader) (Envelope, error) {
	var header [4]byte
	if _, err := io.ReadFull(r, header[:]); err != nil {
		return Envelope{}, err
	}
	size := binary.BigEndian.Uint32(header[:])
	if size == 0 {
		return Envelope{}, ErrFrameEmpty
	}
	if size > MaxFrameBytes {
		return Envelope{}, ErrFrameTooLarge
	}
	body := make([]byte, size)
	if _, err := io.ReadFull(r, body); err != nil {
		return Envelope{}, err
	}
	var env Envelope
	if err := json.Unmarshal(body, &env); err != nil {
		return Envelope{}, fmt.Errorf("invalid json frame: %w", err)
	}
	if env.Version != Version {
		return Envelope{}, ErrVersion
	}
	if env.Type == "" {
		return Envelope{}, errors.New("missing frame type")
	}
	return env, nil
}

func Payload(value any) json.RawMessage {
	data, err := json.Marshal(value)
	if err != nil {
		panic(err)
	}
	return data
}

func RandomBytes(n int) ([]byte, error) {
	out := make([]byte, n)
	_, err := io.ReadFull(rand.Reader, out)
	return out, err
}

func Proof(secret []byte, role string, clientNonce, serverNonce []byte) []byte {
	mac := hmac.New(sha256.New, secret)
	_, _ = mac.Write([]byte("cloudos-core/v1/"))
	_, _ = mac.Write([]byte(role))
	_, _ = mac.Write([]byte{0})
	_, _ = mac.Write(clientNonce)
	_, _ = mac.Write(serverNonce)
	return mac.Sum(nil)
}

func ProofBase64(secret []byte, role string, clientNonce, serverNonce []byte) string {
	return base64.StdEncoding.EncodeToString(Proof(secret, role, clientNonce, serverNonce))
}

func VerifyProof(secret []byte, role string, clientNonce, serverNonce []byte, candidate string) bool {
	decoded, err := base64.StdEncoding.DecodeString(candidate)
	if err != nil {
		return false
	}
	return hmac.Equal(decoded, Proof(secret, role, clientNonce, serverNonce))
}

func DecodeFixedBase64(value string, length int) ([]byte, error) {
	decoded, err := base64.StdEncoding.DecodeString(value)
	if err != nil || len(decoded) != length {
		return nil, errors.New("invalid base64 value")
	}
	return decoded, nil
}
