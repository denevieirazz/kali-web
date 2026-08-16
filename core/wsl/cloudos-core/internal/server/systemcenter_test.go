package server

import (
	"bytes"
	"encoding/json"
	"io"
	"net"
	"os"
	"testing"
	"time"

	"github.com/denevieirazz/kali-web/core/wsl/cloudos-core/internal/protocol"
)

func TestProtectedSystemCenterReadOnlyRPCs(t *testing.T) {
	secret := bytes.Repeat([]byte{12}, protocol.SecretBytes)
	serverSide, clientSide := net.Pipe()
	srv := &Server{secret: secret, distro: DistroInfo{ID: "test"}, system: newSystemCenterRuntime(false)}
	defer srv.system.Close()
	result := make(chan error, 1)
	go func() { result <- srv.serveConnection(serverSide, io.Discard) }()
	secure := authenticateTestClient(t, clientSide, secret)

	listed := requestTest(t, secure, "proc-list", "process.list", map[string]any{"page": 1, "pageSize": 5, "sortBy": "pid"})
	if listed.OK == nil || !*listed.OK {
		t.Fatalf("process.list failed: %+v", listed.Error)
	}
	var page struct {
		Processes []struct {
			PID int `json:"pid"`
		} `json:"processes"`
		PageSize int `json:"pageSize"`
		Total    int `json:"total"`
	}
	if json.Unmarshal(listed.Payload, &page) != nil || page.PageSize > 5 || page.Total < len(page.Processes) {
		t.Fatalf("invalid page: %+v", page)
	}

	metrics := requestTest(t, secure, "metrics", "system.metrics", nil)
	if metrics.OK == nil || !*metrics.OK {
		t.Fatalf("system.metrics failed: %+v", metrics.Error)
	}
	var snapshot struct {
		UptimeSeconds      float64 `json:"uptimeSeconds"`
		ProcessCount       int     `json:"processCount"`
		CgroupCapabilities struct {
			ReadOnly       bool `json:"readOnly"`
			ControlEnabled bool `json:"controlEnabled"`
		} `json:"cgroupCapabilities"`
	}
	if json.Unmarshal(metrics.Payload, &snapshot) != nil || snapshot.UptimeSeconds <= 0 || snapshot.ProcessCount <= 0 || !snapshot.CgroupCapabilities.ReadOnly || snapshot.CgroupCapabilities.ControlEnabled {
		t.Fatalf("invalid metrics: %+v", snapshot)
	}

	caps := requestTest(t, secure, "caps", "cgroup.capabilities", nil)
	if caps.OK == nil || !*caps.OK {
		t.Fatalf("cgroup.capabilities failed: %+v", caps.Error)
	}

	blocked := requestTest(t, secure, "cgroup-write", "cgroup.policy.apply", map[string]any{"pid": os.Getpid(), "startTimeTicks": 1, "policy": map[string]any{"pidsMax": 64}})
	if blocked.OK == nil || *blocked.OK || blocked.Error == nil || blocked.Error.Code != "CGROUP_CONTROL_DISABLED" {
		t.Fatalf("read-only cgroup write not blocked: %+v", blocked)
	}

	shutdown := requestTest(t, secure, "shutdown", "shutdown", nil)
	if shutdown.OK == nil || !*shutdown.OK {
		t.Fatalf("shutdown failed: %+v", shutdown.Error)
	}
	_ = clientSide.Close()
	select {
	case err := <-result:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("server shutdown timed out")
	}
}

func TestSystemCenterBlocksCoreSignalAndShellRPC(t *testing.T) {
	secret := bytes.Repeat([]byte{13}, protocol.SecretBytes)
	serverSide, clientSide := net.Pipe()
	srv := &Server{secret: secret, distro: DistroInfo{ID: "test"}, system: newSystemCenterRuntime(false)}
	defer srv.system.Close()
	result := make(chan error, 1)
	go func() { result <- srv.serveConnection(serverSide, io.Discard) }()
	secure := authenticateTestClient(t, clientSide, secret)

	self := requestTest(t, secure, "self", "process.get", map[string]any{"pid": os.Getpid()})
	if self.OK == nil || !*self.OK {
		t.Fatalf("process.get self failed: %+v", self.Error)
	}
	var p struct {
		Start     uint64 `json:"startTimeTicks"`
		Protected bool   `json:"protected"`
	}
	if json.Unmarshal(self.Payload, &p) != nil || !p.Protected || p.Start == 0 {
		t.Fatalf("self not protected: %+v", p)
	}
	denied := requestTest(t, secure, "sig", "process.signal", map[string]any{"pid": os.Getpid(), "startTimeTicks": p.Start, "signal": "SIGTERM"})
	if denied.OK == nil || *denied.OK || denied.Error == nil || denied.Error.Code != "PROCESS_PROTECTED" {
		t.Fatalf("core signal not blocked: %+v", denied)
	}

	shell := requestTest(t, secure, "shell", "session.create", map[string]any{"executable": "/bin/sh", "args": []string{"-c", "id"}})
	if shell.OK == nil || *shell.OK || shell.Error == nil || shell.Error.Code != "EXECUTABLE_DENIED" {
		t.Fatalf("shell unexpectedly allowed: %+v", shell)
	}
	_ = requestTest(t, secure, "shutdown", "shutdown", nil)
	_ = clientSide.Close()
	select {
	case <-result:
	case <-time.After(3 * time.Second):
		t.Fatal("server shutdown timed out")
	}
}
