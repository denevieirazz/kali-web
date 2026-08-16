package linuxproc

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"os/user"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unicode"
)

const (
	DefaultPageSize = 50
	MaxPageSize     = 100
	MaxProcesses    = 4096
	MaxCmdlineBytes = 4096
	MaxArgBytes     = 256
	ReadBudget      = 1500 * time.Millisecond
)

var sensitiveNames = []string{"password", "passwd", "token", "secret", "api_key", "apikey", "authorization", "credential", "jwt", "nonce", "private_key", "private-key"}
var protectedNames = map[string]struct{}{
	"init": {}, "systemd": {}, "wsl-init": {}, "systemd-journald": {}, "systemd-logind": {}, "systemd-udevd": {},
	"systemd-resolved": {}, "systemd-timesyncd": {}, "systemd-networkd": {}, "systemd-oomd": {}, "systemd-userdbd": {},
	"dbus-daemon": {}, "dbus-broker": {}, "NetworkManager": {}, "polkitd": {}, "agetty": {}, "login": {}, "sshd": {}, "cron": {}, "rsyslogd": {},
}

type Process struct {
	PID             int      `json:"pid"`
	PPID            int      `json:"ppid"`
	State           string   `json:"state"`
	UID             int      `json:"uid"`
	User            string   `json:"user"`
	Name            string   `json:"name"`
	Executable      string   `json:"executable,omitempty"`
	Args            []string `json:"args,omitempty"`
	CPUPercent      float64  `json:"cpuPercent"`
	RSSBytes        uint64   `json:"rssBytes"`
	VirtualBytes    uint64   `json:"virtualBytes"`
	Threads         int      `json:"threads"`
	StartTimeTicks  uint64   `json:"startTimeTicks"`
	UptimeSeconds   float64  `json:"uptimeSeconds,omitempty"`
	Cgroup          string   `json:"cgroup,omitempty"`
	Protected       bool     `json:"protected"`
	ProtectedReason string   `json:"protectedReason,omitempty"`
}

type ListOptions struct {
	Page     int    `json:"page"`
	PageSize int    `json:"pageSize"`
	Query    string `json:"query,omitempty"`
	State    string `json:"state,omitempty"`
	User     string `json:"user,omitempty"`
	SortBy   string `json:"sortBy,omitempty"`
	SortDir  string `json:"sortDir,omitempty"`
}

type ListResult struct {
	Processes []Process `json:"processes"`
	Total     int       `json:"total"`
	Page      int       `json:"page"`
	PageSize  int       `json:"pageSize"`
	Truncated bool      `json:"truncated"`
	SampledAt string    `json:"sampledAt"`
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

type sample struct{ procTicks, totalTicks uint64 }

type Inspector struct {
	procRoot     string
	pageSize     int
	mu           sync.Mutex
	previous     map[int]sample
	signalWindow time.Time
	signalCount  int
}

func NewInspector() *Inspector { return NewInspectorForRoot("/proc") }
func NewInspectorForRoot(root string) *Inspector {
	return &Inspector{procRoot: filepath.Clean(root), pageSize: os.Getpagesize(), previous: map[int]sample{}}
}

func (i *Inspector) List(options ListOptions) (ListResult, error) {
	started := time.Now()
	totalTicks, _ := i.readTotalTicks()
	uptime, _ := i.readUptime()
	entries, err := os.ReadDir(i.procRoot)
	if err != nil {
		return ListResult{}, coded("PROC_UNAVAILABLE")
	}
	processes := make([]Process, 0, min(len(entries), MaxProcesses))
	truncated := false
	for _, entry := range entries {
		if time.Since(started) > ReadBudget {
			truncated = true
			break
		}
		if !entry.IsDir() {
			continue
		}
		pid, err := strconv.Atoi(entry.Name())
		if err != nil || pid <= 0 {
			continue
		}
		if len(processes) >= MaxProcesses {
			truncated = true
			break
		}
		process, err := i.readProcess(pid, totalTicks, uptime)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) || errors.Is(err, syscall.ESRCH) || errors.Is(err, syscall.ENOENT) || errors.Is(err, syscall.EACCES) || errors.Is(err, syscall.EPERM) {
				continue
			}
			continue
		}
		if !matches(process, options) {
			continue
		}
		processes = append(processes, process)
	}
	i.sort(processes, options.SortBy, options.SortDir)
	page := options.Page
	if page < 1 {
		page = 1
	}
	pageSize := options.PageSize
	if pageSize < 1 {
		pageSize = DefaultPageSize
	}
	if pageSize > MaxPageSize {
		pageSize = MaxPageSize
	}
	total := len(processes)
	start := (page - 1) * pageSize
	if start > total {
		start = total
	}
	end := start + pageSize
	if end > total {
		end = total
	}
	return ListResult{Processes: append([]Process(nil), processes[start:end]...), Total: total, Page: page, PageSize: pageSize, Truncated: truncated, SampledAt: time.Now().UTC().Format(time.RFC3339Nano)}, nil
}

func (i *Inspector) Get(pid int) (Process, error) {
	if pid <= 0 {
		return Process{}, coded("PID_INVALID")
	}
	total, _ := i.readTotalTicks()
	uptime, _ := i.readUptime()
	p, err := i.readProcess(pid, total, uptime)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) || errors.Is(err, syscall.ENOENT) || errors.Is(err, syscall.ESRCH) {
			return Process{}, coded("PROCESS_NOT_FOUND")
		}
		if errors.Is(err, syscall.EACCES) || errors.Is(err, syscall.EPERM) {
			return Process{}, coded("PROCESS_DENIED")
		}
		return Process{}, coded("PROCESS_READ_FAILED")
	}
	return p, nil
}

func (i *Inspector) Signal(pid int, expectedStart uint64, name string) error {
	if pid <= 1 {
		return coded("PROCESS_PROTECTED")
	}
	if pid == os.Getpid() {
		return coded("PROCESS_PROTECTED")
	}
	i.mu.Lock()
	now := time.Now()
	if i.signalWindow.IsZero() || now.Sub(i.signalWindow) >= 10*time.Second {
		i.signalWindow = now
		i.signalCount = 0
	}
	if i.signalCount >= 6 {
		i.mu.Unlock()
		return coded("SIGNAL_RATE_LIMIT")
	}
	i.signalCount++
	i.mu.Unlock()

	current, err := i.Get(pid)
	if err != nil {
		return err
	}
	if current.Protected {
		return coded("PROCESS_PROTECTED")
	}
	if expectedStart == 0 || current.StartTimeTicks != expectedStart {
		return coded("PID_REUSED")
	}
	if current.UID != os.Geteuid() {
		return coded("PROCESS_DENIED")
	}
	if again, err := i.Get(pid); err != nil || again.StartTimeTicks != expectedStart || again.Protected {
		if err != nil {
			return err
		}
		if again.Protected {
			return coded("PROCESS_PROTECTED")
		}
		return coded("PID_REUSED")
	}
	var sig syscall.Signal
	switch strings.ToUpper(strings.TrimSpace(name)) {
	case "SIGINT", "INT", "INTERRUPT":
		sig = syscall.SIGINT
	case "SIGTERM", "TERM", "TERMINATE":
		sig = syscall.SIGTERM
	case "SIGKILL", "KILL":
		sig = syscall.SIGKILL
	default:
		return coded("SIGNAL_INVALID")
	}
	if err := syscall.Kill(pid, sig); err != nil {
		if errors.Is(err, syscall.ESRCH) {
			return coded("PROCESS_NOT_FOUND")
		}
		if errors.Is(err, syscall.EPERM) {
			return coded("PROCESS_DENIED")
		}
		return coded("SIGNAL_FAILED")
	}
	return nil
}

func (i *Inspector) readProcess(pid int, totalTicks uint64, uptime float64) (Process, error) {
	base := filepath.Join(i.procRoot, strconv.Itoa(pid))
	statData, err := os.ReadFile(filepath.Join(base, "stat"))
	if err != nil {
		return Process{}, err
	}
	stat, err := parseStat(string(statData))
	if err != nil {
		return Process{}, err
	}
	statusData, err := os.ReadFile(filepath.Join(base, "status"))
	if err != nil {
		return Process{}, err
	}
	status := parseStatus(string(statusData))
	process := Process{PID: pid, PPID: stat.ppid, State: stat.state, UID: status.uid, User: lookupUser(status.uid), Name: stat.name, RSSBytes: status.rssBytes, VirtualBytes: status.virtualBytes, Threads: status.threads, StartTimeTicks: stat.startTime}
	if process.Threads <= 0 {
		process.Threads = stat.threads
	}
	if process.VirtualBytes == 0 {
		process.VirtualBytes = stat.virtualBytes
	}
	if process.RSSBytes == 0 && stat.rssPages > 0 {
		process.RSSBytes = uint64(stat.rssPages) * uint64(i.pageSize)
	}
	if exe, err := os.Readlink(filepath.Join(base, "exe")); err == nil && len(exe) <= 1024 {
		process.Executable = cleanPrintable(exe, 1024)
	}
	if raw, err := os.ReadFile(filepath.Join(base, "cmdline")); err == nil {
		process.Args = sanitizeCmdline(raw)
	}
	if raw, err := os.ReadFile(filepath.Join(base, "cgroup")); err == nil {
		process.Cgroup = parseCgroup(string(raw))
	}
	if pid == 1 {
		process.Protected = true
		process.ProtectedReason = "pid-1"
	} else if pid == os.Getpid() {
		process.Protected = true
		process.ProtectedReason = "cloudos-core"
	} else if process.PPID == 0 || (process.UID == 0 && process.Executable == "" && len(process.Args) == 0) {
		process.Protected = true
		process.ProtectedReason = "kernel-or-system"
	} else if _, ok := protectedNames[process.Name]; ok {
		process.Protected = true
		process.ProtectedReason = "essential"
	}
	hz := 100.0
	if uptime > 0 && stat.startTime > 0 {
		process.UptimeSeconds = uptime - float64(stat.startTime)/hz
		if process.UptimeSeconds < 0 {
			process.UptimeSeconds = 0
		}
	}
	process.CPUPercent = i.cpuPercent(pid, stat.procTicks, totalTicks)
	return process, nil
}

type statRecord struct {
	name, state                        string
	ppid, threads                      int
	procTicks, startTime, virtualBytes uint64
	rssPages                           int64
}

func parseStat(raw string) (statRecord, error) {
	raw = strings.TrimSpace(raw)
	open := strings.IndexByte(raw, '(')
	close := strings.LastIndex(raw, ") ")
	if open < 0 || close <= open {
		return statRecord{}, coded("PROC_STAT_INVALID")
	}
	name := raw[open+1 : close]
	fields := strings.Fields(raw[close+2:])
	if len(fields) < 22 {
		return statRecord{}, coded("PROC_STAT_INVALID")
	}
	ppid, e1 := strconv.Atoi(fields[1])
	utime, e2 := strconv.ParseUint(fields[11], 10, 64)
	stime, e3 := strconv.ParseUint(fields[12], 10, 64)
	threads, e4 := strconv.Atoi(fields[17])
	start, e5 := strconv.ParseUint(fields[19], 10, 64)
	vsize, e6 := strconv.ParseUint(fields[20], 10, 64)
	rss, e7 := strconv.ParseInt(fields[21], 10, 64)
	if e1 != nil || e2 != nil || e3 != nil || e4 != nil || e5 != nil || e6 != nil || e7 != nil {
		return statRecord{}, coded("PROC_STAT_INVALID")
	}
	return statRecord{name: cleanPrintable(name, 256), state: fields[0], ppid: ppid, threads: threads, procTicks: utime + stime, startTime: start, virtualBytes: vsize, rssPages: rss}, nil
}

type statusRecord struct {
	uid, threads           int
	rssBytes, virtualBytes uint64
}

func parseStatus(raw string) statusRecord {
	result := statusRecord{uid: -1}
	scanner := bufio.NewScanner(strings.NewReader(raw))
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "Uid:") {
			f := strings.Fields(line)
			if len(f) > 1 {
				result.uid, _ = strconv.Atoi(f[1])
			}
		}
		if strings.HasPrefix(line, "Threads:") {
			f := strings.Fields(line)
			if len(f) > 1 {
				result.threads, _ = strconv.Atoi(f[1])
			}
		}
		if strings.HasPrefix(line, "VmRSS:") {
			result.rssBytes = parseKB(line)
		}
		if strings.HasPrefix(line, "VmSize:") {
			result.virtualBytes = parseKB(line)
		}
	}
	return result
}
func parseKB(line string) uint64 {
	f := strings.Fields(line)
	if len(f) < 2 {
		return 0
	}
	v, _ := strconv.ParseUint(f[1], 10, 64)
	return v * 1024
}
func parseCgroup(raw string) string {
	for _, line := range strings.Split(raw, "\n") {
		if strings.HasPrefix(line, "0::") {
			p := strings.TrimSpace(strings.TrimPrefix(line, "0::"))
			if strings.HasPrefix(p, "/") {
				return cleanPrintable(p, 1024)
			}
		}
	}
	return ""
}
func sanitizeCmdline(raw []byte) []string {
	if len(raw) > MaxCmdlineBytes {
		raw = raw[:MaxCmdlineBytes]
	}
	parts := strings.Split(string(raw), "\x00")
	out := make([]string, 0, len(parts))
	redactNext := false
	for _, part := range parts {
		if part == "" {
			continue
		}
		value := cleanPrintable(part, MaxArgBytes)
		if redactNext {
			out = append(out, "[REDACTED]")
			redactNext = false
			continue
		}
		lower := strings.ToLower(value)
		if idx := strings.Index(lower, "="); idx > 0 && isSensitiveName(strings.TrimLeft(lower[:idx], "-")) {
			out = append(out, value[:idx+1]+"[REDACTED]")
			continue
		}
		if isSensitiveName(strings.TrimLeft(lower, "-")) {
			out = append(out, value)
			redactNext = true
			continue
		}
		if looksSensitiveValue(value) {
			out = append(out, "[REDACTED]")
			continue
		}
		out = append(out, value)
		if len(out) >= 64 {
			break
		}
	}
	return out
}

func looksSensitiveValue(value string) bool {
	if len(value) < 32 || len(value) > MaxArgBytes {
		return false
	}
	allowed := 0
	for _, r := range value {
		if unicode.IsLetter(r) || unicode.IsDigit(r) || strings.ContainsRune("_-.+/=", r) {
			allowed++
		}
	}
	return allowed == len([]rune(value))
}
func isSensitiveName(name string) bool {
	name = strings.ReplaceAll(strings.ReplaceAll(name, "-", "_"), ".", "_")
	for _, s := range sensitiveNames {
		if name == s || strings.HasSuffix(name, "_"+s) {
			return true
		}
	}
	return false
}
func cleanPrintable(value string, max int) string {
	var b strings.Builder
	for _, r := range value {
		if unicode.IsPrint(r) || r == '\t' {
			b.WriteRune(r)
		}
	}
	s := b.String()
	if len(s) > max {
		s = s[:max]
	}
	return s
}
func lookupUser(uid int) string {
	if uid < 0 {
		return "unknown"
	}
	raw := strconv.Itoa(uid)
	if u, err := user.LookupId(raw); err == nil && u.Username != "" {
		return u.Username
	}
	return raw
}
func matches(p Process, o ListOptions) bool {
	q := strings.ToLower(strings.TrimSpace(o.Query))
	if q != "" {
		hay := strings.ToLower(fmt.Sprintf("%s %s %d %s", p.Name, strings.Join(p.Args, " "), p.PID, p.Executable))
		if !strings.Contains(hay, q) {
			return false
		}
	}
	if s := strings.TrimSpace(o.State); s != "" && !strings.EqualFold(p.State, s) {
		return false
	}
	if u := strings.TrimSpace(o.User); u != "" && !strings.EqualFold(p.User, u) && u != strconv.Itoa(p.UID) {
		return false
	}
	return true
}
func (i *Inspector) sort(ps []Process, by, dir string) {
	desc := strings.EqualFold(dir, "desc")
	less := func(a, b Process) bool {
		switch strings.ToLower(by) {
		case "cpu":
			return a.CPUPercent < b.CPUPercent
		case "memory", "rss":
			return a.RSSBytes < b.RSSBytes
		case "name":
			return strings.ToLower(a.Name) < strings.ToLower(b.Name)
		case "user":
			return strings.ToLower(a.User) < strings.ToLower(b.User)
		default:
			return a.PID < b.PID
		}
	}
	sort.SliceStable(ps, func(a, b int) bool {
		v := less(ps[a], ps[b])
		if desc {
			return less(ps[b], ps[a])
		}
		return v
	})
}
func (i *Inspector) cpuPercent(pid int, proc, total uint64) float64 {
	i.mu.Lock()
	defer i.mu.Unlock()
	prev, ok := i.previous[pid]
	i.previous[pid] = sample{proc, total}
	if !ok || total <= prev.totalTicks || proc < prev.procTicks {
		return 0
	}
	value := float64(proc-prev.procTicks) / float64(total-prev.totalTicks) * float64(runtime.NumCPU()) * 100
	max := float64(runtime.NumCPU()) * 100
	if value < 0 {
		return 0
	}
	if value > max {
		return max
	}
	return value
}
func (i *Inspector) readTotalTicks() (uint64, error) {
	raw, err := os.ReadFile(filepath.Join(i.procRoot, "stat"))
	if err != nil {
		return 0, err
	}
	first := strings.SplitN(string(raw), "\n", 2)[0]
	f := strings.Fields(first)
	if len(f) < 2 || f[0] != "cpu" {
		return 0, coded("PROC_STAT_INVALID")
	}
	var total uint64
	for _, x := range f[1:] {
		v, e := strconv.ParseUint(x, 10, 64)
		if e == nil {
			total += v
		}
	}
	return total, nil
}
func (i *Inspector) readUptime() (float64, error) {
	raw, err := os.ReadFile(filepath.Join(i.procRoot, "uptime"))
	if err != nil {
		return 0, err
	}
	f := strings.Fields(string(raw))
	if len(f) == 0 {
		return 0, coded("PROC_UPTIME_INVALID")
	}
	return strconv.ParseFloat(f[0], 64)
}
