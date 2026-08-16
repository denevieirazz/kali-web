package protocol

import (
	"crypto/aes"
	"crypto/cipher"
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
	Version            = 2
	MaxFrameBytes      = 1 << 20
	MaxIOBytes         = 64 << 10
	NonceBytes         = 32
	SecretBytes        = 32
	SecureTagBytes     = 16
	SecurePrefixBytes  = 4
	SecureSequenceSize = 8
)

var (
	ErrFrameTooLarge = errors.New("frame exceeds protocol limit")
	ErrFrameEmpty    = errors.New("empty frame")
	ErrVersion       = errors.New("unsupported protocol version")
	ErrIntegrity     = errors.New("protected frame integrity check failed")
	ErrSequence      = errors.New("protected frame sequence is invalid")
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

type channelMaterial struct {
	c2sKey, s2cKey       []byte
	c2sPrefix, s2cPrefix [SecurePrefixBytes]byte
}

type SecureChannel struct {
	r io.Reader
	w io.Writer

	readAEAD  cipher.AEAD
	writeAEAD cipher.AEAD

	readPrefix  [SecurePrefixBytes]byte
	writePrefix [SecurePrefixBytes]byte
	readLabel   string
	writeLabel  string

	readSeq  uint64
	writeSeq uint64
	writeMu  sync.Mutex
}

func Payload(value any) json.RawMessage {
	data, err := json.Marshal(value)
	if err != nil {
		panic(err)
	}
	return data
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
	return writeLengthPrefixed(w, body)
}

func ReadFrame(r io.Reader) (Envelope, error) {
	body, err := readLengthPrefixed(r, MaxFrameBytes)
	if err != nil {
		return Envelope{}, err
	}
	return decodeEnvelope(body)
}

func NewSecureChannel(r io.Reader, w io.Writer, secret, clientNonce, serverNonce []byte, serverSide bool) (*SecureChannel, error) {
	if len(secret) != SecretBytes || len(clientNonce) != NonceBytes || len(serverNonce) != NonceBytes {
		return nil, errors.New("invalid secure channel material")
	}
	material, err := deriveChannelMaterial(secret, clientNonce, serverNonce)
	if err != nil {
		return nil, err
	}
	defer zero(material.c2sKey)
	defer zero(material.s2cKey)

	c2sBlock, err := aes.NewCipher(material.c2sKey)
	if err != nil {
		return nil, err
	}
	s2cBlock, err := aes.NewCipher(material.s2cKey)
	if err != nil {
		return nil, err
	}
	c2sAEAD, err := cipher.NewGCMWithTagSize(c2sBlock, SecureTagBytes)
	if err != nil {
		return nil, err
	}
	s2cAEAD, err := cipher.NewGCMWithTagSize(s2cBlock, SecureTagBytes)
	if err != nil {
		return nil, err
	}

	channel := &SecureChannel{r: r, w: w}
	if serverSide {
		channel.readAEAD = c2sAEAD
		channel.writeAEAD = s2cAEAD
		channel.readPrefix = material.c2sPrefix
		channel.writePrefix = material.s2cPrefix
		channel.readLabel = "c2s"
		channel.writeLabel = "s2c"
	} else {
		channel.readAEAD = s2cAEAD
		channel.writeAEAD = c2sAEAD
		channel.readPrefix = material.s2cPrefix
		channel.writePrefix = material.c2sPrefix
		channel.readLabel = "s2c"
		channel.writeLabel = "c2s"
	}
	return channel, nil
}

func (c *SecureChannel) Write(env Envelope) error {
	c.writeMu.Lock()
	defer c.writeMu.Unlock()

	if c.writeSeq == ^uint64(0) {
		return ErrSequence
	}
	seq := c.writeSeq + 1
	if env.Version == 0 {
		env.Version = Version
	}
	plaintext, err := json.Marshal(env)
	if err != nil {
		return err
	}
	if len(plaintext) == 0 {
		return ErrFrameEmpty
	}
	if len(plaintext) > MaxFrameBytes {
		return ErrFrameTooLarge
	}

	nonce := makeNonce(c.writePrefix, seq)
	aad := makeAAD(c.writeLabel, seq)
	ciphertext := c.writeAEAD.Seal(nil, nonce[:], plaintext, aad)
	body := make([]byte, SecureSequenceSize+len(ciphertext))
	binary.BigEndian.PutUint64(body[:SecureSequenceSize], seq)
	copy(body[SecureSequenceSize:], ciphertext)
	if err := writeLengthPrefixed(c.w, body); err != nil {
		return err
	}
	c.writeSeq = seq
	return nil
}

func (c *SecureChannel) Read() (Envelope, error) {
	max := MaxFrameBytes + SecureSequenceSize + SecureTagBytes
	body, err := readLengthPrefixed(c.r, max)
	if err != nil {
		return Envelope{}, err
	}
	if len(body) < SecureSequenceSize+SecureTagBytes {
		return Envelope{}, ErrIntegrity
	}
	seq := binary.BigEndian.Uint64(body[:SecureSequenceSize])
	if c.readSeq == ^uint64(0) || seq != c.readSeq+1 {
		return Envelope{}, ErrSequence
	}
	nonce := makeNonce(c.readPrefix, seq)
	aad := makeAAD(c.readLabel, seq)
	plaintext, err := c.readAEAD.Open(nil, nonce[:], body[SecureSequenceSize:], aad)
	if err != nil {
		return Envelope{}, ErrIntegrity
	}
	if len(plaintext) == 0 || len(plaintext) > MaxFrameBytes {
		return Envelope{}, ErrFrameTooLarge
	}
	env, err := decodeEnvelope(plaintext)
	if err != nil {
		return Envelope{}, err
	}
	c.readSeq = seq
	return env, nil
}

func decodeEnvelope(body []byte) (Envelope, error) {
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

func writeLengthPrefixed(w io.Writer, body []byte) error {
	var header [4]byte
	binary.BigEndian.PutUint32(header[:], uint32(len(body)))
	if _, err := w.Write(header[:]); err != nil {
		return err
	}
	_, err := w.Write(body)
	return err
}

func readLengthPrefixed(r io.Reader, max int) ([]byte, error) {
	var header [4]byte
	if _, err := io.ReadFull(r, header[:]); err != nil {
		return nil, err
	}
	size := binary.BigEndian.Uint32(header[:])
	if size == 0 {
		return nil, ErrFrameEmpty
	}
	if uint64(size) > uint64(max) {
		return nil, ErrFrameTooLarge
	}
	body := make([]byte, int(size))
	if _, err := io.ReadFull(r, body); err != nil {
		return nil, err
	}
	return body, nil
}

func Proof(secret []byte, role string, clientNonce, serverNonce []byte) []byte {
	mac := hmac.New(sha256.New, secret)
	_, _ = mac.Write([]byte("cloudos-core/v2/"))
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

func RandomBytes(n int) ([]byte, error) {
	out := make([]byte, n)
	_, err := io.ReadFull(rand.Reader, out)
	return out, err
}

func deriveChannelMaterial(secret, clientNonce, serverNonce []byte) (channelMaterial, error) {
	context := make([]byte, 0, 32+len(clientNonce)+len(serverNonce))
	context = append(context, []byte("cloudos-core/v2/hkdf-salt")...)
	context = append(context, 0)
	context = append(context, clientNonce...)
	context = append(context, serverNonce...)
	salt := sha256.Sum256(context)

	extract := hmac.New(sha256.New, salt[:])
	_, _ = extract.Write(secret)
	prk := extract.Sum(nil)
	defer zero(prk)

	c2sKey, err := hkdfExpand(prk, []byte("cloudos-core/v2/c2s/key"), 32)
	if err != nil {
		return channelMaterial{}, err
	}
	s2cKey, err := hkdfExpand(prk, []byte("cloudos-core/v2/s2c/key"), 32)
	if err != nil {
		zero(c2sKey)
		return channelMaterial{}, err
	}
	c2sNonce, err := hkdfExpand(prk, []byte("cloudos-core/v2/c2s/nonce"), SecurePrefixBytes)
	if err != nil {
		zero(c2sKey)
		zero(s2cKey)
		return channelMaterial{}, err
	}
	s2cNonce, err := hkdfExpand(prk, []byte("cloudos-core/v2/s2c/nonce"), SecurePrefixBytes)
	if err != nil {
		zero(c2sKey)
		zero(s2cKey)
		zero(c2sNonce)
		return channelMaterial{}, err
	}
	var out channelMaterial
	out.c2sKey = c2sKey
	out.s2cKey = s2cKey
	copy(out.c2sPrefix[:], c2sNonce)
	copy(out.s2cPrefix[:], s2cNonce)
	zero(c2sNonce)
	zero(s2cNonce)
	return out, nil
}

func hkdfExpand(prk, info []byte, length int) ([]byte, error) {
	if length <= 0 || length > 255*sha256.Size {
		return nil, errors.New("invalid hkdf length")
	}
	result := make([]byte, 0, length)
	previous := []byte(nil)
	for counter := byte(1); len(result) < length; counter++ {
		mac := hmac.New(sha256.New, prk)
		_, _ = mac.Write(previous)
		_, _ = mac.Write(info)
		_, _ = mac.Write([]byte{counter})
		previous = mac.Sum(nil)
		needed := length - len(result)
		if needed > len(previous) {
			needed = len(previous)
		}
		result = append(result, previous[:needed]...)
	}
	zero(previous)
	return result, nil
}

func makeNonce(prefix [SecurePrefixBytes]byte, seq uint64) [12]byte {
	var nonce [12]byte
	copy(nonce[:SecurePrefixBytes], prefix[:])
	binary.BigEndian.PutUint64(nonce[SecurePrefixBytes:], seq)
	return nonce
}

func makeAAD(direction string, seq uint64) []byte {
	prefix := []byte("cloudos-core/v2/secure/" + direction)
	aad := make([]byte, len(prefix)+1+SecureSequenceSize)
	copy(aad, prefix)
	binary.BigEndian.PutUint64(aad[len(prefix)+1:], seq)
	return aad
}

func zero(value []byte) {
	for i := range value {
		value[i] = 0
	}
}
