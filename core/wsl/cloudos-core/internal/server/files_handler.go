package server

import (
	"encoding/json"

	filecore "github.com/denevieirazz/kali-web/core/wsl/cloudos-core/internal/files"
	"github.com/denevieirazz/kali-web/core/wsl/cloudos-core/internal/protocol"
)

func handleFilesRequest(method string, params json.RawMessage, writer *protocol.SecureChannel, id string) (bool, error) {
	if len(method) < 3 || method[:3] != "fs." {
		return false, nil
	}
	manager, err := filecore.NewManager()
	if err != nil {
		return true, coded(filecore.Code(err))
	}
	defer manager.Close()

	fail := func(err error) (bool, error) {
		if err == nil {
			return true, nil
		}
		return true, coded(filecore.Code(err))
	}
	decode := func(target any) error {
		if len(params) == 0 || string(params) == "null" {
			return nil
		}
		if json.Unmarshal(params, target) != nil {
			return coded("REQUEST_INVALID")
		}
		return nil
	}

	switch method {
	case "fs.info":
		return true, writeOK(writer, id, manager.Info())
	case "fs.list":
		var request struct{ Path []string `json:"path"` }
		if err := decode(&request); err != nil { return true, err }
		entries, err := manager.List(request.Path)
		if err != nil { return fail(err) }
		return true, writeOK(writer, id, map[string]any{"path": request.Path, "entries": entries})
	case "fs.read":
		var request struct {
			Path   []string `json:"path"`
			Offset int64    `json:"offset"`
			Limit  int      `json:"limit"`
		}
		if err := decode(&request); err != nil { return true, err }
		result, err := manager.Read(request.Path, request.Offset, request.Limit)
		if err != nil { return fail(err) }
		return true, writeOK(writer, id, result)
	case "fs.write":
		var request struct {
			Path     []string `json:"path"`
			Offset   int64    `json:"offset"`
			Data     string   `json:"data"`
			Truncate bool     `json:"truncate"`
			Mode     uint32   `json:"mode"`
		}
		if err := decode(&request); err != nil { return true, err }
		result, err := manager.Write(request.Path, request.Offset, request.Data, request.Truncate, request.Mode)
		if err != nil { return fail(err) }
		return true, writeOK(writer, id, result)
	case "fs.mkdir":
		var request struct {
			Path []string `json:"path"`
			Mode uint32   `json:"mode"`
		}
		if err := decode(&request); err != nil { return true, err }
		if err := manager.Mkdir(request.Path, request.Mode); err != nil { return fail(err) }
		return true, writeOK(writer, id, map[string]bool{"created": true})
	case "fs.rename", "fs.move":
		var request struct {
			Source      []string `json:"source"`
			Destination []string `json:"destination"`
		}
		if err := decode(&request); err != nil { return true, err }
		if err := manager.Rename(request.Source, request.Destination); err != nil { return fail(err) }
		return true, writeOK(writer, id, map[string]bool{"moved": true})
	case "fs.copy":
		var request struct {
			Source      []string `json:"source"`
			Destination []string `json:"destination"`
		}
		if err := decode(&request); err != nil { return true, err }
		result, err := manager.Copy(request.Source, request.Destination)
		if err != nil { return fail(err) }
		return true, writeOK(writer, id, result)
	case "fs.trash":
		var request struct{ Path []string `json:"path"` }
		if err := decode(&request); err != nil { return true, err }
		result, err := manager.Trash(request.Path)
		if err != nil { return fail(err) }
		return true, writeOK(writer, id, result)
	case "fs.trash.list":
		entries, err := manager.ListTrash()
		if err != nil { return fail(err) }
		return true, writeOK(writer, id, map[string]any{"entries": entries})
	case "fs.trash.restore":
		var request struct{ ID string `json:"id"` }
		if err := decode(&request); err != nil { return true, err }
		result, err := manager.Restore(request.ID)
		if err != nil { return fail(err) }
		return true, writeOK(writer, id, result)
	case "fs.trash.delete":
		var request struct{ ID string `json:"id"` }
		if err := decode(&request); err != nil { return true, err }
		if err := manager.DeleteTrash(request.ID); err != nil { return fail(err) }
		return true, writeOK(writer, id, map[string]bool{"deleted": true})
	default:
		return true, coded("METHOD_NOT_FOUND")
	}
}
