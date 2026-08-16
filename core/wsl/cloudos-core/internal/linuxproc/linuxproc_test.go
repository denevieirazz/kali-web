package linuxproc

import (
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestParseStatHandlesSpacesAndParentheses(t *testing.T) {
	raw := "123 (weird ) name) S 1 0 0 0 0 0 0 0 0 0 10 5 0 0 0 0 3 0 4242 8192 5 0"
	stat, err := parseStat(raw)
	if err != nil { t.Fatal(err) }
	if stat.name != "weird ) name" || stat.ppid != 1 || stat.startTime != 4242 { t.Fatalf("unexpected %+v", stat) }
}
func TestSanitizeCmdlineRedactsAndLimits(t *testing.T) {
	raw := []byte("tool\x00--token\x00supersecret\x00--api-key=value\x00safe\x00")
	args := sanitizeCmdline(raw); joined := strings.Join(args, " ")
	if strings.Contains(joined, "supersecret") || strings.Contains(joined, "=value") { t.Fatalf("secret leaked: %q", joined) }
	if !strings.Contains(joined, "[REDACTED]") { t.Fatalf("missing redaction: %q", joined) }
}
func TestSanitizeCmdlineRedactsHighEntropyPositionalValue(t *testing.T) {
	raw := []byte("tool\x00ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdef\x00short-value\x00")
	args := sanitizeCmdline(raw); joined := strings.Join(args, " ")
	if strings.Contains(joined, "ABCDEFGHIJKLMNOPQRSTUVWXYZ") || !strings.Contains(joined, "[REDACTED]") { t.Fatalf("high entropy positional value leaked: %q", joined) }
}
func TestListSkipsDisappearingProcessAndPaginates(t *testing.T) {
	root := t.TempDir(); mustWrite(t, filepath.Join(root, "stat"), "cpu  10 0 10 100 0 0 0 0 0 0\n"); mustWrite(t, filepath.Join(root, "uptime"), "100.00 1.00\n")
	makeFakeProcess(t, root, 101, "alpha", "S", 1, 1000, "alpha\x00--token\x00hidden\x00"); makeFakeProcess(t, root, 102, "beta", "S", 1, 1001, "beta\x00"); _ = os.Mkdir(filepath.Join(root, "103"), 0755)
	inspector := NewInspectorForRoot(root); result, err := inspector.List(ListOptions{Page:1, PageSize:1, SortBy:"pid"}); if err != nil { t.Fatal(err) }
	if result.Total != 2 || len(result.Processes) != 1 || result.Processes[0].PID != 101 { t.Fatalf("unexpected %+v", result) }
	if strings.Contains(strings.Join(result.Processes[0].Args, " "), "hidden") { t.Fatal("cmdline secret leaked") }
}
func TestGetRejectsInvalidPID(t *testing.T) { if _, err := NewInspectorForRoot(t.TempDir()).Get(0); Code(err) != "PID_INVALID" { t.Fatalf("got %s", Code(err)) } }
func TestSignalChecksIdentityAndSignalsBenignChild(t *testing.T) {
	cmd := exec.Command("/bin/sleep", "30"); if err := cmd.Start(); err != nil { t.Skipf("sleep unavailable: %v", err) }; defer func(){ _=cmd.Process.Kill(); _,_=cmd.Process.Wait() }()
	inspector := NewInspector(); var p Process; var err error; deadline := time.Now().Add(2*time.Second)
	for time.Now().Before(deadline) { p,err=inspector.Get(cmd.Process.Pid); if err==nil {break}; time.Sleep(10*time.Millisecond) }
	if err != nil {t.Fatal(err)}; if err:=inspector.Signal(p.PID,p.StartTimeTicks+1,"SIGTERM"); Code(err)!="PID_REUSED" {t.Fatalf("expected PID_REUSED got %s",Code(err))}
	if err:=inspector.Signal(p.PID,p.StartTimeTicks,"SIGTERM"); err!=nil {t.Fatal(err)}; done:=make(chan error,1); go func(){done<-cmd.Wait()}(); select{case <-done: case <-time.After(2*time.Second): t.Fatal("process did not exit")}
}
func TestPIDOneProtected(t *testing.T) { if err:=NewInspector().Signal(1,1,"SIGTERM"); Code(err)!="PROCESS_PROTECTED" {t.Fatalf("got %s",Code(err))} }
func makeFakeProcess(t *testing.T, root string, pid int, name,state string,ppid int,start uint64,cmdline string){t.Helper();dir:=filepath.Join(root,strconv.Itoa(pid));if err:=os.MkdirAll(dir,0755);err!=nil{t.Fatal(err)};stat:=strconv.Itoa(pid)+" ("+name+") "+state+" "+strconv.Itoa(ppid)+" 0 0 0 0 0 0 0 0 0 10 5 0 0 0 0 2 0 "+strconv.FormatUint(start,10)+" 8192 2 0\n";mustWrite(t,filepath.Join(dir,"stat"),stat);mustWrite(t,filepath.Join(dir,"status"),"Name:\t"+name+"\nUid:\t"+strconv.Itoa(os.Geteuid())+"\t"+strconv.Itoa(os.Geteuid())+"\t0\t0\nVmRSS:\t4 kB\nVmSize:\t8 kB\nThreads:\t2\n");mustWrite(t,filepath.Join(dir,"cmdline"),cmdline);mustWrite(t,filepath.Join(dir,"cgroup"),"0::/user.slice/cloudos\n")}
func mustWrite(t *testing.T,path,content string){t.Helper();if err:=os.MkdirAll(filepath.Dir(path),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(path,[]byte(content),0644);err!=nil{t.Fatal(err)}}
