package server

import (
	"encoding/json"

	"github.com/denevieirazz/kali-web/core/wsl/cloudos-core/internal/cgroups"
	"github.com/denevieirazz/kali-web/core/wsl/cloudos-core/internal/linuxproc"
	"github.com/denevieirazz/kali-web/core/wsl/cloudos-core/internal/metrics"
	"github.com/denevieirazz/kali-web/core/wsl/cloudos-core/internal/protocol"
)

type systemCenterRuntime struct {
	processes *linuxproc.Inspector
	cgroups   *cgroups.Manager
}

func newSystemCenterRuntime(controlEnabled bool) *systemCenterRuntime {
	return &systemCenterRuntime{processes: linuxproc.NewInspector(), cgroups: cgroups.NewManagerWithOptions(cgroups.Options{ControlEnabled: controlEnabled})}
}

func (r *systemCenterRuntime) Close() { r.cgroups.Close() }

func (r *systemCenterRuntime) handle(method string, params json.RawMessage, writer *protocol.SecureChannel, id string) (bool, error) {
	switch method {
	case "process.list":
		var options linuxproc.ListOptions
		if len(params) > 0 && string(params) != "null" && json.Unmarshal(params, &options) != nil {
			return true, coded("REQUEST_INVALID")
		}
		result, err := r.processes.List(options)
		if err != nil {
			return true, coded(linuxproc.Code(err))
		}
		return true, writeOK(writer, id, result)
	case "process.get":
		var request struct {
			PID int `json:"pid"`
		}
		if json.Unmarshal(params, &request) != nil {
			return true, coded("REQUEST_INVALID")
		}
		result, err := r.processes.Get(request.PID)
		if err != nil {
			return true, coded(linuxproc.Code(err))
		}
		return true, writeOK(writer, id, result)
	case "process.signal":
		var request struct {
			PID            int    `json:"pid"`
			StartTimeTicks uint64 `json:"startTimeTicks"`
			Signal         string `json:"signal"`
		}
		if json.Unmarshal(params, &request) != nil {
			return true, coded("REQUEST_INVALID")
		}
		if err := r.processes.Signal(request.PID, request.StartTimeTicks, request.Signal); err != nil {
			return true, coded(linuxproc.Code(err))
		}
		return true, writeOK(writer, id, map[string]bool{"accepted": true})
	case "system.metrics":
		snapshot, err := metrics.Read()
		if err != nil {
			return true, coded("METRICS_UNAVAILABLE")
		}
		capabilities := r.cgroups.Capabilities()
		cgMetrics, _ := r.cgroups.Metrics(capabilities.CurrentPath)
		result := struct {
			UptimeSeconds        float64                         `json:"uptimeSeconds"`
			Load1                float64                         `json:"load1"`
			Load5                float64                         `json:"load5"`
			Load15               float64                         `json:"load15"`
			MemoryTotalBytes     uint64                          `json:"memoryTotalBytes"`
			MemoryAvailableBytes uint64                          `json:"memoryAvailableBytes"`
			ProcessCount         int                             `json:"processCount"`
			CgroupV2             bool                            `json:"cgroupV2"`
			CgroupPath           string                          `json:"cgroupPath,omitempty"`
			CgroupMetrics        map[string]string               `json:"cgroupMetrics,omitempty"`
			CgroupCapabilities   cgroups.LinuxCgroupCapabilities `json:"cgroupCapabilities"`
			ResourceMetrics      cgroups.LinuxResourceMetrics    `json:"resourceMetrics"`
		}{
			UptimeSeconds: snapshot.UptimeSeconds, Load1: snapshot.Load1, Load5: snapshot.Load5, Load15: snapshot.Load15,
			MemoryTotalBytes: snapshot.Memory.TotalBytes, MemoryAvailableBytes: snapshot.Memory.AvailableBytes, ProcessCount: snapshot.ProcessCount,
			CgroupV2: snapshot.CgroupV2, CgroupPath: snapshot.CgroupPath, CgroupMetrics: snapshot.Cgroup,
			CgroupCapabilities: capabilities, ResourceMetrics: cgMetrics,
		}
		return true, writeOK(writer, id, result)
	case "cgroup.capabilities":
		capabilities := r.cgroups.Capabilities()
		cgMetrics, _ := r.cgroups.Metrics(capabilities.CurrentPath)
		return true, writeOK(writer, id, map[string]any{"capabilities": capabilities, "metrics": cgMetrics})
	case "cgroup.policy.apply":
		var request struct {
			PID            int                         `json:"pid"`
			StartTimeTicks uint64                      `json:"startTimeTicks"`
			Policy         cgroups.LinuxResourcePolicy `json:"policy"`
		}
		if json.Unmarshal(params, &request) != nil {
			return true, coded("REQUEST_INVALID")
		}
		assignment, err := r.cgroups.Apply(request.PID, request.StartTimeTicks, request.Policy)
		if err != nil {
			return true, coded(cgroups.Code(err))
		}
		return true, writeOK(writer, id, assignment)
	case "cgroup.policy.clear":
		var request struct {
			ID string `json:"id"`
		}
		if json.Unmarshal(params, &request) != nil || request.ID == "" {
			return true, coded("REQUEST_INVALID")
		}
		if err := r.cgroups.Clear(request.ID); err != nil {
			return true, coded(cgroups.Code(err))
		}
		return true, writeOK(writer, id, map[string]bool{"cleared": true})
	case "cgroup.assignment.get":
		var request struct {
			ID string `json:"id"`
		}
		if json.Unmarshal(params, &request) != nil || request.ID == "" {
			return true, coded("REQUEST_INVALID")
		}
		assignment, err := r.cgroups.GetAssignment(request.ID)
		if err != nil {
			return true, coded(cgroups.Code(err))
		}
		return true, writeOK(writer, id, assignment)
	default:
		return false, nil
	}
}
