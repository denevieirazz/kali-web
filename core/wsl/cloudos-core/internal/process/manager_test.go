package process

import (
	"encoding/base64"
	"errors"
	"os"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestRejectsShellAndPreservesArgumentBoundaries(t *testing.T) {
	manager := NewManager(nil)
	if _, err := manager.Create("owner", CreateOptions{Executable: "/bin/sh", Args: []string{"-c", "echo unsafe"}}); Code(err) != "EXECUTABLE_DENIED" {
		t.Fatalf("shell accepted: %v", err)
	}
	events := make(chan Event, 8)
	manager = NewManager(func(e Event) { events <- e })
	status, err := manager.Create("owner", CreateOptions{Executable: "/bin/echo", Args: []string{"alpha;uname", "$(id)"}})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := manager.Wait("owner", status.SessionID, 3*time.Second); err != nil {
		t.Fatal(err)
	}
	deadline := time.After(2 * time.Second)
	var output strings.Builder
	for !strings.Contains(output.String(), "alpha;uname $(id)") {
		select {
		case event := <-events:
			if event.Type == "session.output" {
				decoded, _ := base64.StdEncoding.DecodeString(event.Data)
				output.Write(decoded)
			}
		case <-deadline:
			t.Fatalf("argument boundary changed: %q", output.String())
		}
	}
}

func TestEnvironmentIsBuiltFromAllowlist(t *testing.T) {
	t.Setenv("JWT_SECRET", "must-not-leak")
	t.Setenv("API_TOKEN", "must-not-leak")
	env := strings.Join(buildEnv(map[string]string{"TERM": "xterm-test"}), "\n")
	if strings.Contains(env, "must-not-leak") || strings.Contains(env, "JWT_SECRET") || strings.Contains(env, "API_TOKEN") {
		t.Fatalf("secret inherited: %s", env)
	}
	if !strings.Contains(env, "TERM=xterm-test") {
		t.Fatalf("allowed override missing: %s", env)
	}
	if _, err := NewManager(nil).Create("owner", CreateOptions{Executable: "/bin/echo", Env: map[string]string{"JWT_SECRET": "x"}}); Code(err) != "ENV_INVALID" {
		t.Fatalf("forbidden env accepted: %v", err)
	}
}

func TestOwnerIsolationSignalAndCleanup(t *testing.T) {
	manager := NewManager(nil)
	status, err := manager.Create("owner-a", CreateOptions{Executable: "/bin/sleep", Args: []string{"30"}})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := manager.Status("owner-b", status.SessionID); Code(err) != "SESSION_NOT_OWNED" {
		t.Fatalf("foreign session visible: %v", err)
	}
	if err := manager.Signal("owner-a", status.SessionID, "terminate"); err != nil {
		t.Fatal(err)
	}
	exited, err := manager.Wait("owner-a", status.SessionID, 4*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	if exited.State != "exited" {
		t.Fatalf("session did not exit: %+v", exited)
	}

	second, err := manager.Create("owner-a", CreateOptions{Executable: "/bin/sleep", Args: []string{"30"}})
	if err != nil {
		t.Fatal(err)
	}
	pid := second.PID
	manager.CloseOwner("owner-a")
	for i := 0; i < 30; i++ {
		err := syscall.Kill(pid, 0)
		if errors.Is(err, syscall.ESRCH) {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	if process, err := os.FindProcess(pid); err == nil && process != nil {
		_ = process.Kill()
	}
	t.Fatalf("process %d survived owner cleanup", pid)
}

func TestPTYResizeInputAndExit(t *testing.T) {
	events := make(chan Event, 16)
	manager := NewManager(func(e Event) { events <- e })
	status, err := manager.Create("owner", CreateOptions{Executable: "/bin/cat", PTY: true, Rows: 24, Cols: 80})
	if err != nil {
		t.Fatal(err)
	}
	if err := manager.Resize("owner", status.SessionID, 40, 120); err != nil {
		t.Fatal(err)
	}
	if err := manager.Input("owner", status.SessionID, []byte("cloudos-pty\n")); err != nil {
		t.Fatal(err)
	}
	deadline := time.After(3 * time.Second)
	seen := false
	for !seen {
		select {
		case event := <-events:
			if event.Type == "session.output" {
				decoded, _ := base64.StdEncoding.DecodeString(event.Data)
				if strings.Contains(string(decoded), "cloudos-pty") {
					seen = true
				}
			}
		case <-deadline:
			t.Fatal("PTY output not observed")
		}
	}
	if err := manager.Signal("owner", status.SessionID, "terminate"); err != nil {
		t.Fatal(err)
	}
	if _, err := manager.Wait("owner", status.SessionID, 4*time.Second); err != nil {
		t.Fatal(err)
	}
}

func TestLimitsAreEnforced(t *testing.T) {
	manager := NewManager(nil)
	defer manager.CloseAll()
	args := make([]string, MaxArgs+1)
	if _, err := manager.Create("owner", CreateOptions{Executable: "/bin/echo", Args: args}); Code(err) != "ARGUMENT_LIMIT" {
		t.Fatalf("argument limit not enforced: %v", err)
	}
	env := make(map[string]string, MaxEnvEntries+1)
	for i := 0; i < MaxEnvEntries+1; i++ {
		env["TERM"+strings.Repeat("X", i)] = "x"
	}
	if _, err := manager.Create("owner", CreateOptions{Executable: "/bin/echo", Env: env}); Code(err) != "ENV_LIMIT" {
		t.Fatalf("environment limit not enforced: %v", err)
	}

	cat, err := manager.Create("owner", CreateOptions{Executable: "/bin/cat"})
	if err != nil {
		t.Fatal(err)
	}
	if err := manager.Input("owner", cat.SessionID, make([]byte, MaxIOBytes+1)); Code(err) != "IO_LIMIT" {
		t.Fatalf("I/O limit not enforced: %v", err)
	}
	_ = manager.Signal("owner", cat.SessionID, "terminate")
	_, _ = manager.Wait("owner", cat.SessionID, 3*time.Second)

	for i := 0; i < MaxSessions; i++ {
		if _, err := manager.Create("limit-owner", CreateOptions{Executable: "/bin/sleep", Args: []string{"30"}}); err != nil {
			t.Fatalf("session %d should be allowed: %v", i, err)
		}
	}
	if _, err := manager.Create("limit-owner", CreateOptions{Executable: "/bin/sleep", Args: []string{"30"}}); Code(err) != "SESSION_LIMIT" {
		t.Fatalf("session limit not enforced: %v", err)
	}
	manager.CloseOwner("limit-owner")
}
