package server

import (
	"bufio"
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/user"
	"strconv"
	"strings"
	"time"

	"github.com/denevieirazz/kali-web/core/wsl/cloudos-core/internal/metrics"
	processcore "github.com/denevieirazz/kali-web/core/wsl/cloudos-core/internal/process"
	"github.com/denevieirazz/kali-web/core/wsl/cloudos-core/internal/protocol"
)

const bootstrapTimeout = 30 * time.Second

type Bootstrap struct {
	Protocol int        `json:"protocol"`
	Port     int        `json:"port"`
	PID      int        `json:"pid"`
	Distro   DistroInfo `json:"distro"`
}
type DistroInfo struct {
	ID         string `json:"id"`
	VersionID  string `json:"versionId,omitempty"`
	PrettyName string `json:"prettyName,omitempty"`
	User       string `json:"user"`
	Systemd    bool   `json:"systemd"`
}
type helloPayload struct {
	ClientNonce string `json:"clientNonce"`
}
type proofPayload struct {
	Proof string `json:"proof"`
}
type Server struct {
	secret []byte
	distro DistroInfo
	system *systemCenterRuntime
}

type Options struct{ CgroupControl bool }

func Run(stdin io.Reader, stdout, stderr io.Writer) error {
	return RunWithOptions(stdin, stdout, stderr, Options{})
}

func RunWithOptions(stdin io.Reader, stdout, stderr io.Writer, options Options) error {
	secret, err := readSecret(stdin)
	if err != nil {
		return err
	}
	defer zero(secret)
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		return errors.New("loopback listen failed")
	}
	defer listener.Close()
	tcpListener := listener.(*net.TCPListener)
	_ = tcpListener.SetDeadline(time.Now().Add(bootstrapTimeout))
	distro := identifyDistro()
	port := listener.Addr().(*net.TCPAddr).Port
	bootstrap, _ := json.Marshal(Bootstrap{Protocol: protocol.Version, Port: port, PID: os.Getpid(), Distro: distro})
	if _, err := fmt.Fprintf(stdout, "%s\n", bootstrap); err != nil {
		return errors.New("bootstrap output failed")
	}
	conn, err := listener.Accept()
	if err != nil {
		return errors.New("client connection timeout")
	}
	_ = listener.Close()
	defer conn.Close()
	if tcp, ok := conn.(*net.TCPConn); ok {
		_ = tcp.SetKeepAlive(true)
		_ = tcp.SetKeepAlivePeriod(15 * time.Second)
	}
	srv := &Server{secret: secret, distro: distro, system: newSystemCenterRuntime(options.CgroupControl)}
	defer srv.system.Close()
	return srv.serveConnection(conn, stderr)
}

func (s *Server) serveConnection(conn net.Conn, stderr io.Writer) error {
	owner, channel, err := s.authenticate(conn)
	if err != nil {
		return err
	}
	manager := processcore.NewManager(func(event processcore.Event) {
		_ = channel.Write(protocol.Envelope{Type: "event", Payload: protocol.Payload(event)})
	})
	defer manager.CloseOwner(owner)
	for {
		_ = conn.SetReadDeadline(time.Now().Add(90 * time.Second))
		env, err := channel.Read()
		if err != nil {
			if errors.Is(err, io.EOF) || errors.Is(err, net.ErrClosed) {
				return nil
			}
			return errors.New("protected protocol read failed")
		}
		if env.Type == "ping" {
			_ = channel.Write(protocol.Envelope{Type: "pong", ID: env.ID})
			continue
		}
		if env.Type != "request" || env.ID == "" {
			_ = writeError(channel, env.ID, "REQUEST_INVALID")
			continue
		}
		shutdown, err := s.handleRequest(owner, manager, channel, env)
		if err != nil {
			code := processcore.Code(err)
			if code == "INTERNAL_ERROR" {
				code = errorCode(err)
			}
			_ = writeError(channel, env.ID, code)
		}
		if shutdown {
			manager.CloseOwner(owner)
			return nil
		}
	}
}

func (s *Server) authenticate(conn net.Conn) (string, *protocol.SecureChannel, error) {
	_ = conn.SetDeadline(time.Now().Add(10 * time.Second))
	hello, err := protocol.ReadFrame(conn)
	if err != nil || hello.Type != "hello" {
		return "", nil, errors.New("authentication failed")
	}
	var hp helloPayload
	if json.Unmarshal(hello.Payload, &hp) != nil {
		return "", nil, errors.New("authentication failed")
	}
	clientNonce, err := protocol.DecodeFixedBase64(hp.ClientNonce, protocol.NonceBytes)
	if err != nil {
		return "", nil, errors.New("authentication failed")
	}
	defer zero(clientNonce)
	serverNonce := make([]byte, protocol.NonceBytes)
	if _, err := rand.Read(serverNonce); err != nil {
		return "", nil, errors.New("authentication failed")
	}
	defer zero(serverNonce)
	challenge := struct {
		ServerNonce string `json:"serverNonce"`
		Proof       string `json:"proof"`
	}{base64.StdEncoding.EncodeToString(serverNonce), protocol.ProofBase64(s.secret, "server", clientNonce, serverNonce)}
	if err := protocol.WriteFrame(conn, protocol.Envelope{Type: "challenge", Payload: protocol.Payload(challenge)}); err != nil {
		return "", nil, errors.New("authentication failed")
	}
	proof, err := protocol.ReadFrame(conn)
	if err != nil || proof.Type != "proof" {
		return "", nil, errors.New("authentication failed")
	}
	var pp proofPayload
	if json.Unmarshal(proof.Payload, &pp) != nil || !protocol.VerifyProof(s.secret, "client", clientNonce, serverNonce, pp.Proof) {
		return "", nil, errors.New("authentication failed")
	}
	channel, err := protocol.NewSecureChannel(conn, conn, s.secret, clientNonce, serverNonce, true)
	if err != nil {
		return "", nil, errors.New("authentication failed")
	}
	ownerBytes := make([]byte, 16)
	if _, err := rand.Read(ownerBytes); err != nil {
		return "", nil, errors.New("authentication failed")
	}
	owner := base64.RawURLEncoding.EncodeToString(ownerBytes)
	zero(ownerBytes)
	if err := channel.Write(protocol.Envelope{Type: "ready", Payload: protocol.Payload(map[string]any{"connectionId": owner, "protocol": protocol.Version, "protection": "aes-256-gcm-seq"})}); err != nil {
		return "", nil, errors.New("authentication failed")
	}
	_ = conn.SetDeadline(time.Time{})
	return owner, channel, nil
}

func (s *Server) handleRequest(owner string, manager *processcore.Manager, writer *protocol.SecureChannel, env protocol.Envelope) (bool, error) {
	var request struct {
		Method string          `json:"method"`
		Params json.RawMessage `json:"params,omitempty"`
	}
	if err := json.Unmarshal(env.Payload, &request); err != nil || request.Method == "" {
		return false, coded("REQUEST_INVALID")
	}
	if s.system != nil {
		if handled, err := s.system.handle(request.Method, request.Params, writer, env.ID); handled {
			return false, err
		}
	}
	switch request.Method {
	case "health":
		return false, writeOK(writer, env.ID, map[string]any{"status": "ready", "protocol": protocol.Version, "pid": os.Getpid(), "distro": s.distro, "activeSessions": manager.Active(), "protection": "aes-256-gcm-seq"})
	case "metrics.get":
		snapshot, err := metrics.Read()
		if err != nil {
			return false, coded("METRICS_UNAVAILABLE")
		}
		return false, writeOK(writer, env.ID, snapshot)
	case "session.create":
		var o processcore.CreateOptions
		if json.Unmarshal(request.Params, &o) != nil {
			return false, coded("REQUEST_INVALID")
		}
		status, err := manager.Create(owner, o)
		if err != nil {
			return false, err
		}
		return false, writeOK(writer, env.ID, status)
	case "terminal.create":
		var t struct {
			Rows int `json:"rows"`
			Cols int `json:"cols"`
		}
		if len(request.Params) > 0 && string(request.Params) != "null" && json.Unmarshal(request.Params, &t) != nil {
			return false, coded("REQUEST_INVALID")
		}
		status, err := manager.CreateTerminal(owner, t.Rows, t.Cols)
		if err != nil {
			return false, err
		}
		return false, writeOK(writer, env.ID, status)
	case "session.input":
		var in struct {
			SessionID string `json:"sessionId"`
			Data      string `json:"data"`
		}
		if json.Unmarshal(request.Params, &in) != nil {
			return false, coded("REQUEST_INVALID")
		}
		data, err := base64.StdEncoding.DecodeString(in.Data)
		if err != nil {
			return false, coded("IO_INVALID")
		}
		if err := manager.Input(owner, in.SessionID, data); err != nil {
			return false, err
		}
		return false, writeOK(writer, env.ID, map[string]bool{"accepted": true})
	case "session.resize":
		var r struct {
			SessionID string `json:"sessionId"`
			Rows      int    `json:"rows"`
			Cols      int    `json:"cols"`
		}
		if json.Unmarshal(request.Params, &r) != nil {
			return false, coded("REQUEST_INVALID")
		}
		if err := manager.Resize(owner, r.SessionID, r.Rows, r.Cols); err != nil {
			return false, err
		}
		return false, writeOK(writer, env.ID, map[string]bool{"accepted": true})
	case "session.signal":
		var r struct {
			SessionID string `json:"sessionId"`
			Signal    string `json:"signal"`
		}
		if json.Unmarshal(request.Params, &r) != nil {
			return false, coded("REQUEST_INVALID")
		}
		if err := manager.Signal(owner, r.SessionID, r.Signal); err != nil {
			return false, err
		}
		return false, writeOK(writer, env.ID, map[string]bool{"accepted": true})
	case "session.status":
		var r struct {
			SessionID string `json:"sessionId"`
		}
		if json.Unmarshal(request.Params, &r) != nil {
			return false, coded("REQUEST_INVALID")
		}
		status, err := manager.Status(owner, r.SessionID)
		if err != nil {
			return false, err
		}
		return false, writeOK(writer, env.ID, status)
	case "session.wait":
		var r struct {
			SessionID string `json:"sessionId"`
			TimeoutMs int    `json:"timeoutMs"`
		}
		if json.Unmarshal(request.Params, &r) != nil {
			return false, coded("REQUEST_INVALID")
		}
		status, err := manager.Wait(owner, r.SessionID, time.Duration(r.TimeoutMs)*time.Millisecond)
		if err != nil {
			return false, err
		}
		return false, writeOK(writer, env.ID, status)
	case "shutdown":
		manager.CloseOwner(owner)
		if err := writeOK(writer, env.ID, map[string]bool{"shuttingDown": true}); err != nil {
			return true, err
		}
		return true, nil
	default:
		return false, coded("METHOD_NOT_FOUND")
	}
}

func writeOK(w *protocol.SecureChannel, id string, payload any) error {
	ok := true
	return w.Write(protocol.Envelope{Type: "response", ID: id, OK: &ok, Payload: protocol.Payload(payload)})
}
func writeError(w *protocol.SecureChannel, id, code string) error {
	ok := false
	return w.Write(protocol.Envelope{Type: "response", ID: id, OK: &ok, Error: &protocol.ErrorBody{Code: code, Message: safeMessage(code)}})
}
func safeMessage(code string) string {
	messages := map[string]string{
		"REQUEST_INVALID": "request is invalid", "METHOD_NOT_FOUND": "method is not supported", "EXECUTABLE_DENIED": "executable is not allowed", "ARGUMENT_LIMIT": "argument limit exceeded", "ARGUMENT_INVALID": "argument is invalid", "ENV_LIMIT": "environment limit exceeded", "ENV_INVALID": "environment override is invalid", "USER_DENIED": "requested user is not allowed", "CWD_INVALID": "working directory is invalid", "CWD_DENIED": "working directory is not allowed", "SESSION_LIMIT": "session limit reached", "TERMINAL_SESSION_LIMIT": "only one terminal session is allowed per connection", "SESSION_NOT_FOUND": "session was not found", "SESSION_NOT_OWNED": "session belongs to another connection", "SESSION_NOT_RUNNING": "session is not running", "SESSION_NOT_PTY": "session does not have a pty", "PROCESS_START_FAILED": "process could not be started", "IO_LIMIT": "input exceeds limit", "IO_INVALID": "input is invalid", "SIGNAL_INVALID": "signal is invalid", "WAIT_TIMEOUT": "wait timed out", "METRICS_UNAVAILABLE": "kernel metrics are unavailable",
		"PROC_UNAVAILABLE": "linux process data is unavailable", "PID_INVALID": "pid is invalid", "PROCESS_NOT_FOUND": "process no longer exists", "PROCESS_DENIED": "process action is not allowed", "PROCESS_READ_FAILED": "process could not be read", "PROCESS_PROTECTED": "process is protected", "PID_REUSED": "process identity changed", "SIGNAL_RATE_LIMIT": "signal rate limit reached", "SIGNAL_FAILED": "signal could not be delivered",
		"CGROUP_CONTROL_DISABLED": "cgroup control is disabled", "CGROUP_CONTROL_UNAVAILABLE": "cgroup control is unavailable", "CGROUP_PATH_DENIED": "cgroup path is not allowed", "CGROUP_PROCESS_OUTSIDE_CORE": "process is outside the CloudOS cgroup", "CGROUP_POLICY_EMPTY": "resource policy is empty", "CGROUP_POLICY_INVALID": "resource policy is invalid", "CGROUP_CREATE_FAILED": "resource group could not be created", "CGROUP_WRITE_FAILED": "resource limit could not be written", "CGROUP_ASSIGN_FAILED": "process could not be assigned", "CGROUP_ASSIGNMENT_NOT_FOUND": "resource assignment was not found", "CGROUP_CLEANUP_FAILED": "resource assignment cleanup failed",
	}
	if m := messages[code]; m != "" {
		return m
	}
	return "operation failed"
}

type codedError string

func (e codedError) Error() string { return string(e) }
func coded(code string) error      { return codedError(code) }
func errorCode(err error) string {
	var c codedError
	if errors.As(err, &c) {
		return string(c)
	}
	return "INTERNAL_ERROR"
}
func readSecret(r io.Reader) ([]byte, error) {
	reader := bufio.NewReader(io.LimitReader(r, 512))
	line, err := reader.ReadString('\n')
	if err != nil {
		return nil, errors.New("bootstrap secret missing")
	}
	line = strings.TrimSpace(line)
	decoded, err := base64.StdEncoding.DecodeString(line)
	if err != nil || len(decoded) != protocol.SecretBytes {
		return nil, errors.New("bootstrap secret invalid")
	}
	return decoded, nil
}
func zero(v []byte) {
	for i := range v {
		v[i] = 0
	}
}
func identifyDistro() DistroInfo {
	values := map[string]string{}
	if data, err := os.ReadFile("/etc/os-release"); err == nil {
		for _, line := range strings.Split(string(data), "\n") {
			key, raw, ok := strings.Cut(line, "=")
			if !ok {
				continue
			}
			raw = strings.Trim(strings.TrimSpace(raw), "\"")
			if key == "ID" || key == "VERSION_ID" || key == "PRETTY_NAME" {
				if len(raw) > 160 {
					raw = raw[:160]
				}
				values[key] = raw
			}
		}
	}
	username := os.Getenv("USER")
	if current, err := user.Current(); err == nil && current.Username != "" {
		username = current.Username
	}
	_, statErr := os.Stat("/run/systemd/system")
	return DistroInfo{ID: values["ID"], VersionID: values["VERSION_ID"], PrettyName: values["PRETTY_NAME"], User: username, Systemd: statErr == nil && os.Getppid() > 0}
}
func EqualSecret(left, right []byte) bool {
	if len(left) != len(right) {
		return false
	}
	return subtle.ConstantTimeCompare(left, right) == 1
}
func ParsePort(value string) (int, bool) {
	port, err := strconv.Atoi(value)
	return port, err == nil && port > 0 && port <= 65535
}
