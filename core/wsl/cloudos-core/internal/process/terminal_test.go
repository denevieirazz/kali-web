package process

import (
	"bytes"
	"encoding/base64"
	"strings"
	"testing"
	"time"
)

func TestGenericAllowlistStillRejectsShell(t *testing.T) {
	manager := NewManager(nil)
	defer manager.CloseAll()
	if _, err := manager.Create("owner", CreateOptions{Executable: "/bin/bash", Args: []string{"-lc", "id"}, PTY: true}); Code(err) != "EXECUTABLE_DENIED" {
		t.Fatalf("generic shell unexpectedly allowed: %v", err)
	}
}

func TestFixedTerminalLifecycle(t *testing.T) {
	events := make(chan Event, 16)
	manager := NewManager(func(event Event) { events <- event })
	defer manager.CloseAll()
	status, err := manager.CreateTerminal("owner", 24, 80)
	if err != nil {
		t.Fatal(err)
	}
	if status.SessionID == "" || status.PID <= 0 || !status.PTY {
		t.Fatalf("invalid terminal status: %+v", status)
	}
	if _, err := manager.CreateTerminal("owner", 24, 80); Code(err) != "TERMINAL_SESSION_LIMIT" {
		t.Fatalf("second terminal was not rejected: %v", err)
	}
	if err := manager.Resize("owner", status.SessionID, 30, 100); err != nil {
		t.Fatal(err)
	}
	if err := manager.Input("owner", status.SessionID, []byte("printf 'cloudos-fixed-terminal-ok\\n'\n")); err != nil {
		t.Fatal(err)
	}
	deadline := time.After(3 * time.Second)
	var output bytes.Buffer
	for !strings.Contains(output.String(), "cloudos-fixed-terminal-ok") {
		select {
		case event := <-events:
			if event.Type == "session.output" && event.SessionID == status.SessionID {
				data, _ := base64.StdEncoding.DecodeString(event.Data)
				output.Write(data)
			}
		case <-deadline:
			t.Fatalf("terminal output not observed: %q", output.String())
		}
	}
	if err := manager.Signal("owner", status.SessionID, "hangup"); err != nil {
		t.Fatal(err)
	}
	if _, err := manager.Wait("owner", status.SessionID, 3*time.Second); err != nil {
		t.Fatal(err)
	}
}
