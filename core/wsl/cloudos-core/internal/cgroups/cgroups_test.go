package cgroups

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCapabilitiesReadOnlyWhenFlagDisabled(t *testing.T) {
	root, proc := fakeTree(t, true)
	manager := NewManagerWithOptions(Options{Root: root, ProcRoot: proc, ControlEnabled: false})
	cap := manager.Capabilities()
	if !cap.Mounted || !cap.ReadOnly || cap.ControlAvailable || cap.Reason != "feature-flag-disabled" {
		t.Fatalf("unexpected %+v", cap)
	}
}
func TestCapabilitiesReportsNoDelegation(t *testing.T) {
	root, proc := fakeTree(t, false)
	manager := NewManagerWithOptions(Options{Root: root, ProcRoot: proc, ControlEnabled: true})
	cap := manager.Capabilities()
	if cap.ControlAvailable || cap.Reason == "" {
		t.Fatalf("unexpected %+v", cap)
	}
}
func TestApplyBlockedWithoutFlag(t *testing.T) {
	root, proc := fakeTree(t, true)
	manager := NewManagerWithOptions(Options{Root: root, ProcRoot: proc, ControlEnabled: false})
	p := 64*1024*1024 + 1
	value := uint64(p)
	_, err := manager.Apply(100, 1, LinuxResourcePolicy{MemoryMaxBytes: &value})
	if Code(err) != "CGROUP_CONTROL_DISABLED" {
		t.Fatalf("got %s", Code(err))
	}
}
func TestPathEscapeDenied(t *testing.T) {
	root, proc := fakeTree(t, true)
	manager := NewManagerWithOptions(Options{Root: root, ProcRoot: proc})
	if _, err := manager.Metrics("/../../etc"); Code(err) != "CGROUP_PATH_DENIED" {
		t.Fatalf("got %s", Code(err))
	}
}
func TestPolicyValidationConservative(t *testing.T) {
	cap := LinuxCgroupCapabilities{ControllerSupport: map[string]bool{"memory": true, "cpu": true, "pids": true}}
	small := uint64(1024)
	if err := validatePolicy(LinuxResourcePolicy{MemoryMaxBytes: &small}, cap); Code(err) != "CGROUP_POLICY_INVALID" {
		t.Fatalf("got %s", Code(err))
	}
	cpu := 500
	if err := validatePolicy(LinuxResourcePolicy{CPUPercent: &cpu}, cap); Code(err) != "CGROUP_POLICY_INVALID" {
		t.Fatalf("got %s", Code(err))
	}
}
func fakeTree(t *testing.T, delegated bool) (string, string) {
	t.Helper()
	root := t.TempDir()
	proc := t.TempDir()
	current := filepath.Join(root, "user.slice", "cloudos")
	if err := os.MkdirAll(current, 0755); err != nil {
		t.Fatal(err)
	}
	must(t, filepath.Join(root, "cgroup.controllers"), "cpu memory pids\n")
	must(t, filepath.Join(current, "cgroup.controllers"), "cpu memory pids\n")
	if delegated {
		must(t, filepath.Join(current, "cgroup.subtree_control"), "cpu memory pids\n")
	} else {
		must(t, filepath.Join(current, "cgroup.subtree_control"), "\n")
	}
	for _, name := range []string{"cgroup.procs", "memory.max", "memory.high", "cpu.max", "pids.max", "memory.current", "pids.current", "cpu.stat"} {
		must(t, filepath.Join(current, name), "0\n")
	}
	if err := os.MkdirAll(filepath.Join(proc, "self"), 0755); err != nil {
		t.Fatal(err)
	}
	must(t, filepath.Join(proc, "self", "cgroup"), "0::/user.slice/cloudos\n")
	return root, proc
}
func must(t *testing.T, path, value string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(value), 0644); err != nil {
		t.Fatal(err)
	}
}
