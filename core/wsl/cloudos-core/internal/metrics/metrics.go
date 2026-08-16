package metrics

import (
	"bufio"
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

type Snapshot struct {
	UptimeSeconds float64           `json:"uptimeSeconds"`
	Load1         float64           `json:"load1"`
	Load5         float64           `json:"load5"`
	Load15        float64           `json:"load15"`
	Memory        MemorySnapshot    `json:"memory"`
	ProcessCount  int               `json:"processCount"`
	CgroupV2      bool              `json:"cgroupV2"`
	CgroupPath    string            `json:"cgroupPath,omitempty"`
	Cgroup        map[string]string `json:"cgroup,omitempty"`
}

type MemorySnapshot struct {
	TotalBytes     uint64 `json:"totalBytes"`
	AvailableBytes uint64 `json:"availableBytes"`
}

func Read() (Snapshot, error) {
	uptimeFields, err := fields("/proc/uptime")
	if err != nil || len(uptimeFields) < 1 {
		return Snapshot{}, errors.New("proc uptime unavailable")
	}
	uptime, err := strconv.ParseFloat(uptimeFields[0], 64)
	if err != nil {
		return Snapshot{}, errors.New("invalid proc uptime")
	}
	loadFields, err := fields("/proc/loadavg")
	if err != nil || len(loadFields) < 3 {
		return Snapshot{}, errors.New("proc loadavg unavailable")
	}
	load1, _ := strconv.ParseFloat(loadFields[0], 64)
	load5, _ := strconv.ParseFloat(loadFields[1], 64)
	load15, _ := strconv.ParseFloat(loadFields[2], 64)
	memory, err := readMemory()
	if err != nil {
		return Snapshot{}, err
	}
	count, err := countProcesses()
	if err != nil {
		return Snapshot{}, err
	}
	cgroupPath := readCgroupV2Path()
	cgroupValues := map[string]string{}
	cgroupV2 := false
	if _, err := os.Stat("/sys/fs/cgroup/cgroup.controllers"); err == nil {
		cgroupV2 = true
		base := filepath.Clean(filepath.Join("/sys/fs/cgroup", cgroupPath))
		root := filepath.Clean("/sys/fs/cgroup")
		if base == root || strings.HasPrefix(base, root+string(os.PathSeparator)) {
			for _, name := range []string{"memory.current", "memory.max", "pids.current", "cpu.stat"} {
				if data, err := os.ReadFile(filepath.Join(base, name)); err == nil {
					value := strings.TrimSpace(string(data))
					if len(value) > 4096 {
						value = value[:4096]
					}
					cgroupValues[name] = value
				}
			}
		}
	}
	return Snapshot{
		UptimeSeconds: uptime,
		Load1:         load1,
		Load5:         load5,
		Load15:        load15,
		Memory:        memory,
		ProcessCount:  count,
		CgroupV2:      cgroupV2,
		CgroupPath:    cgroupPath,
		Cgroup:        cgroupValues,
	}, nil
}

func fields(path string) ([]string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return strings.Fields(string(data)), nil
}

func readMemory() (MemorySnapshot, error) {
	file, err := os.Open("/proc/meminfo")
	if err != nil {
		return MemorySnapshot{}, errors.New("proc meminfo unavailable")
	}
	defer file.Close()
	values := map[string]uint64{}
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		parts := strings.Fields(scanner.Text())
		if len(parts) < 2 {
			continue
		}
		value, err := strconv.ParseUint(parts[1], 10, 64)
		if err == nil {
			values[strings.TrimSuffix(parts[0], ":")] = value * 1024
		}
	}
	if err := scanner.Err(); err != nil {
		return MemorySnapshot{}, errors.New("proc meminfo read failed")
	}
	if values["MemTotal"] == 0 {
		return MemorySnapshot{}, errors.New("proc meminfo incomplete")
	}
	return MemorySnapshot{TotalBytes: values["MemTotal"], AvailableBytes: values["MemAvailable"]}, nil
}

func countProcesses() (int, error) {
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return 0, errors.New("proc process list unavailable")
	}
	count := 0
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		if _, err := strconv.Atoi(entry.Name()); err == nil {
			count++
		}
	}
	return count, nil
}

func readCgroupV2Path() string {
	data, err := os.ReadFile("/proc/self/cgroup")
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(data), "\n") {
		if strings.HasPrefix(line, "0::") {
			return strings.TrimPrefix(strings.TrimSpace(line), "0::")
		}
	}
	return ""
}
