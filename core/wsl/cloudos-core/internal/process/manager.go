package process

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/creack/pty"
)

const (
	MaxSessions   = 8
	MaxArgs       = 64
	MaxArgBytes   = 4096
	MaxEnvEntries = 16
	MaxIOBytes    = 64 << 10
)

var allowedExecutables = map[string]struct{}{
	"/bin/cat": {}, "/bin/echo": {}, "/bin/sleep": {},
	"/usr/bin/cat": {}, "/usr/bin/echo": {}, "/usr/bin/id": {},
	"/usr/bin/printf": {}, "/usr/bin/sleep": {}, "/usr/bin/uname": {},
}

var allowedEnv = map[string]struct{}{
	"LANG": {}, "LC_ALL": {}, "LC_CTYPE": {}, "TERM": {}, "COLORTERM": {},
}

type Event struct {
	Type      string `json:"type"`
	SessionID string `json:"sessionId"`
	Stream    string `json:"stream,omitempty"`
	Data      string `json:"data,omitempty"`
	ExitCode  *int   `json:"exitCode,omitempty"`
	Signal    string `json:"signal,omitempty"`
}

type CreateOptions struct {
	Executable string            `json:"executable"`
	Args       []string          `json:"args"`
	Cwd        string            `json:"cwd,omitempty"`
	Env        map[string]string `json:"env,omitempty"`
	User       string            `json:"user,omitempty"`
	PTY        bool              `json:"pty,omitempty"`
	Cols       int               `json:"cols,omitempty"`
	Rows       int               `json:"rows,omitempty"`
}

type Status struct {
	SessionID string `json:"sessionId"`
	PID       int    `json:"pid"`
	State     string `json:"state"`
	ExitCode  *int   `json:"exitCode,omitempty"`
	Signal    string `json:"signal,omitempty"`
	PTY       bool   `json:"pty"`
}

type Manager struct {
	mu       sync.RWMutex
	sessions map[string]*Session
	emit     func(Event)
}

type Session struct {
	mu       sync.RWMutex
	id       string
	owner    string
	kind     string
	cmd      *exec.Cmd
	cancel   context.CancelFunc
	stdin    io.WriteCloser
	pty      *os.File
	done     chan struct{}
	state    string
	exitCode *int
	signal   string
	isPTY    bool
}

func NewManager(emit func(Event)) *Manager {
	if emit == nil {
		emit = func(Event) {}
	}
	return &Manager{sessions: make(map[string]*Session), emit: emit}
}

func (m *Manager) Active() int {
	m.mu.RLock()
	defer m.mu.RUnlock()
	count := 0
	for _, session := range m.sessions {
		session.mu.RLock()
		if session.state == "running" {
			count++
		}
		session.mu.RUnlock()
	}
	return count
}

func (m *Manager) Create(owner string, options CreateOptions) (Status, error) {
	if err := validateOptions(options); err != nil {
		return Status{}, err
	}
	return m.create(owner, options, "generic")
}

// CreateTerminal is deliberately separate from the generic executable allowlist.
// It creates one fixed interactive login shell per authenticated connection and
// never accepts an executable, argv, cwd, user or environment from the client.
func (m *Manager) CreateTerminal(owner string, rows, cols int) (Status, error) {
	return m.create(owner, CreateOptions{
		Executable: "/bin/bash",
		Args:       []string{"-l"},
		PTY:        true,
		Rows:       rows,
		Cols:       cols,
	}, "terminal")
}

func (m *Manager) create(owner string, options CreateOptions, kind string) (Status, error) {
	if owner == "" {
		return Status{}, coded("OWNER_INVALID")
	}
	m.mu.Lock()
	running := 0
	for _, existing := range m.sessions {
		existing.mu.RLock()
		if existing.state == "running" {
			running++
			if kind == "terminal" && existing.owner == owner && existing.kind == "terminal" {
				existing.mu.RUnlock()
				m.mu.Unlock()
				return Status{}, coded("TERMINAL_SESSION_LIMIT")
			}
		}
		existing.mu.RUnlock()
	}
	if running >= MaxSessions {
		m.mu.Unlock()
		return Status{}, coded("SESSION_LIMIT")
	}
	id, err := opaqueID()
	if err != nil {
		m.mu.Unlock()
		return Status{}, coded("SESSION_CREATE_FAILED")
	}

	ctx, cancel := context.WithCancel(context.Background())
	cmd := exec.CommandContext(ctx, options.Executable, options.Args...)
	cmd.Dir = normalizedCwd(options.Cwd)
	cmd.Env = buildEnv(options.Env)
	cmd.SysProcAttr = &syscall.SysProcAttr{Pdeathsig: syscall.SIGKILL}

	session := &Session{id: id, owner: owner, kind: kind, cmd: cmd, cancel: cancel, done: make(chan struct{}), state: "starting", isPTY: options.PTY}
	if options.PTY {
		rows, cols := clampSize(options.Rows, options.Cols)
		ptmx, err := pty.StartWithSize(cmd, &pty.Winsize{Rows: uint16(rows), Cols: uint16(cols)})
		if err != nil {
			cancel()
			m.mu.Unlock()
			return Status{}, coded("PROCESS_START_FAILED")
		}
		session.pty = ptmx
		session.stdin = ptmx
	} else {
		stdin, err := cmd.StdinPipe()
		if err != nil {
			cancel()
			m.mu.Unlock()
			return Status{}, coded("PROCESS_START_FAILED")
		}
		stdout, err := cmd.StdoutPipe()
		if err != nil {
			cancel()
			m.mu.Unlock()
			return Status{}, coded("PROCESS_START_FAILED")
		}
		stderr, err := cmd.StderrPipe()
		if err != nil {
			cancel()
			m.mu.Unlock()
			return Status{}, coded("PROCESS_START_FAILED")
		}
		if err := cmd.Start(); err != nil {
			cancel()
			m.mu.Unlock()
			return Status{}, coded("PROCESS_START_FAILED")
		}
		session.stdin = stdin
		go m.copyOutput(session, "stdout", stdout)
		go m.copyOutput(session, "stderr", stderr)
	}
	session.state = "running"
	m.sessions[id] = session
	m.mu.Unlock()

	if options.PTY {
		go m.copyOutput(session, "pty", session.pty)
	}
	go m.wait(session)
	return session.status(), nil
}

func (m *Manager) copyOutput(session *Session, stream string, reader io.Reader) {
	buffer := make([]byte, 32<<10)
	for {
		n, err := reader.Read(buffer)
		if n > 0 {
			m.emit(Event{Type: "session.output", SessionID: session.id, Stream: stream, Data: base64.StdEncoding.EncodeToString(buffer[:n])})
		}
		if err != nil {
			return
		}
	}
}

func (m *Manager) wait(session *Session) {
	err := session.cmd.Wait()
	if session.pty != nil {
		_ = session.pty.Close()
	}
	code := -1
	signal := ""
	if session.cmd.ProcessState != nil {
		code = session.cmd.ProcessState.ExitCode()
		if wait, ok := session.cmd.ProcessState.Sys().(syscall.WaitStatus); ok && wait.Signaled() {
			signal = wait.Signal().String()
		}
	} else if err == nil {
		code = 0
	}
	session.mu.Lock()
	session.state = "exited"
	session.exitCode = &code
	session.signal = signal
	session.mu.Unlock()
	close(session.done)
	m.emit(Event{Type: "session.exit", SessionID: session.id, ExitCode: &code, Signal: signal})
}

func (m *Manager) Input(owner, id string, data []byte) error {
	if len(data) > MaxIOBytes {
		return coded("IO_LIMIT")
	}
	session, err := m.get(owner, id)
	if err != nil {
		return err
	}
	session.mu.RLock()
	running := session.state == "running"
	stdin := session.stdin
	session.mu.RUnlock()
	if !running || stdin == nil {
		return coded("SESSION_NOT_RUNNING")
	}
	_, err = stdin.Write(data)
	if err != nil {
		return coded("SESSION_IO_FAILED")
	}
	return nil
}

func (m *Manager) Resize(owner, id string, rows, cols int) error {
	session, err := m.get(owner, id)
	if err != nil {
		return err
	}
	session.mu.RLock()
	ptmx := session.pty
	running := session.state == "running"
	session.mu.RUnlock()
	if !running || ptmx == nil {
		return coded("SESSION_NOT_PTY")
	}
	rows, cols = clampSize(rows, cols)
	if err := pty.Setsize(ptmx, &pty.Winsize{Rows: uint16(rows), Cols: uint16(cols)}); err != nil {
		return coded("SESSION_RESIZE_FAILED")
	}
	return nil
}

func (m *Manager) Signal(owner, id, name string) error {
	session, err := m.get(owner, id)
	if err != nil {
		return err
	}
	signal, ok := map[string]syscall.Signal{
		"interrupt": syscall.SIGINT,
		"terminate": syscall.SIGTERM,
		"kill":      syscall.SIGKILL,
		"hangup":    syscall.SIGHUP,
	}[strings.ToLower(name)]
	if !ok {
		return coded("SIGNAL_INVALID")
	}
	session.mu.RLock()
	process := session.cmd.Process
	running := session.state == "running"
	isPTY := session.isPTY
	session.mu.RUnlock()
	if !running || process == nil {
		return coded("SESSION_NOT_RUNNING")
	}
	if err := signalProcess(process, isPTY, signal); err != nil {
		return coded("SIGNAL_FAILED")
	}
	return nil
}

func (m *Manager) Status(owner, id string) (Status, error) {
	session, err := m.get(owner, id)
	if err != nil {
		return Status{}, err
	}
	return session.status(), nil
}

func (m *Manager) Wait(owner, id string, timeout time.Duration) (Status, error) {
	session, err := m.get(owner, id)
	if err != nil {
		return Status{}, err
	}
	if timeout <= 0 || timeout > 10*time.Second {
		timeout = 10 * time.Second
	}
	select {
	case <-session.done:
		return session.status(), nil
	case <-time.After(timeout):
		return session.status(), coded("WAIT_TIMEOUT")
	}
}

func (m *Manager) CloseOwner(owner string) {
	m.mu.RLock()
	sessions := make([]*Session, 0, len(m.sessions))
	for _, session := range m.sessions {
		if session.owner == owner {
			sessions = append(sessions, session)
		}
	}
	m.mu.RUnlock()
	for _, session := range sessions {
		terminateSession(session)
	}
}

func (m *Manager) CloseAll() {
	m.mu.RLock()
	sessions := make([]*Session, 0, len(m.sessions))
	for _, session := range m.sessions {
		sessions = append(sessions, session)
	}
	m.mu.RUnlock()
	for _, session := range sessions {
		terminateSession(session)
	}
}

func terminateSession(session *Session) {
	session.mu.RLock()
	running := session.state == "running"
	process := session.cmd.Process
	cancel := session.cancel
	isPTY := session.isPTY
	session.mu.RUnlock()
	if !running {
		return
	}
	if process != nil {
		_ = signalProcess(process, isPTY, syscall.SIGTERM)
	}
	select {
	case <-session.done:
		return
	case <-time.After(800 * time.Millisecond):
	}
	if cancel != nil {
		cancel()
	}
	if process != nil {
		_ = signalProcess(process, isPTY, syscall.SIGKILL)
	}
	select {
	case <-session.done:
	case <-time.After(2 * time.Second):
	}
}

func signalProcess(process *os.Process, isPTY bool, signal syscall.Signal) error {
	if process == nil {
		return errors.New("process is unavailable")
	}
	if isPTY {
		// creack/pty starts the PTY child as a session leader. Signalling the
		// process group reaches the shell and its foreground children, which is
		// required for Ctrl+C/close semantics and orphan-free cleanup.
		return syscall.Kill(-process.Pid, signal)
	}
	return process.Signal(signal)
}

func (m *Manager) get(owner, id string) (*Session, error) {
	m.mu.RLock()
	session := m.sessions[id]
	m.mu.RUnlock()
	if session == nil {
		return nil, coded("SESSION_NOT_FOUND")
	}
	if session.owner != owner {
		return nil, coded("SESSION_NOT_OWNED")
	}
	return session, nil
}

func (s *Session) status() Status {
	s.mu.RLock()
	defer s.mu.RUnlock()
	pid := 0
	if s.cmd.Process != nil {
		pid = s.cmd.Process.Pid
	}
	var exit *int
	if s.exitCode != nil {
		value := *s.exitCode
		exit = &value
	}
	return Status{SessionID: s.id, PID: pid, State: s.state, ExitCode: exit, Signal: s.signal, PTY: s.isPTY}
}

type codedError string

func (e codedError) Error() string { return string(e) }
func coded(code string) error      { return codedError(code) }
func Code(err error) string {
	var c codedError
	if errors.As(err, &c) {
		return string(c)
	}
	return "INTERNAL_ERROR"
}

func validateOptions(options CreateOptions) error {
	if _, ok := allowedExecutables[options.Executable]; !ok {
		return coded("EXECUTABLE_DENIED")
	}
	if len(options.Args) > MaxArgs {
		return coded("ARGUMENT_LIMIT")
	}
	for _, arg := range options.Args {
		if len(arg) > MaxArgBytes || strings.ContainsRune(arg, '\x00') {
			return coded("ARGUMENT_INVALID")
		}
	}
	if len(options.Env) > MaxEnvEntries {
		return coded("ENV_LIMIT")
	}
	for key, value := range options.Env {
		if _, ok := allowedEnv[key]; !ok || len(value) > 256 || strings.ContainsRune(value, '\x00') {
			return coded("ENV_INVALID")
		}
	}
	if options.User != "" {
		current := currentUserName()
		if options.User != current {
			return coded("USER_DENIED")
		}
	}
	if options.Cwd != "" {
		if err := validateCwd(options.Cwd); err != nil {
			return err
		}
	}
	return nil
}

func currentUserName() string {
	if current, err := user.Current(); err == nil && current.Username != "" {
		parts := strings.Split(current.Username, "\\")
		return parts[len(parts)-1]
	}
	return os.Getenv("USER")
}

func normalizedCwd(requested string) string {
	if requested != "" {
		return filepath.Clean(requested)
	}
	if home, err := os.UserHomeDir(); err == nil {
		return home
	}
	return "/tmp"
}

func validateCwd(requested string) error {
	if !filepath.IsAbs(requested) {
		return coded("CWD_INVALID")
	}
	clean := filepath.Clean(requested)
	info, err := os.Stat(clean)
	if err != nil || !info.IsDir() {
		return coded("CWD_INVALID")
	}
	home, _ := os.UserHomeDir()
	allowed := clean == "/tmp" || strings.HasPrefix(clean, "/tmp/") || clean == home || (home != "" && strings.HasPrefix(clean, home+"/"))
	if !allowed {
		return coded("CWD_DENIED")
	}
	return nil
}

func buildEnv(overrides map[string]string) []string {
	home, _ := os.UserHomeDir()
	username := currentUserName()
	values := map[string]string{
		"PATH":    "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
		"HOME":    home,
		"USER":    username,
		"LOGNAME": username,
		"LANG":    "C.UTF-8",
		"TERM":    "xterm-256color",
	}
	for key, value := range overrides {
		if _, ok := allowedEnv[key]; ok {
			values[key] = value
		}
	}
	result := make([]string, 0, len(values))
	for key, value := range values {
		result = append(result, fmt.Sprintf("%s=%s", key, value))
	}
	return result
}

func clampSize(rows, cols int) (int, int) {
	if rows < 5 {
		rows = 5
	}
	if rows > 200 {
		rows = 200
	}
	if cols < 20 {
		cols = 20
	}
	if cols > 400 {
		cols = 400
	}
	return rows, cols
}

func opaqueID() (string, error) {
	raw := make([]byte, 16)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	return hex.EncodeToString(raw), nil
}
