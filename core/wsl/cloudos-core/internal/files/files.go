package files

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/user"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"
)

const (
	MaxSegments   = 64
	MaxNameBytes  = 255
	MaxReadChunk  = 256 * 1024
	MaxWriteChunk = 256 * 1024
	trashDirName  = ".cloudos-trash"
)

type codedError string

func (e codedError) Error() string { return string(e) }
func coded(code string) error      { return codedError(code) }
func Code(err error) string {
	var c codedError
	if errors.As(err, &c) {
		return string(c)
	}
	return "FILES_INTERNAL_ERROR"
}

type Entry struct {
	Name       string `json:"name"`
	Kind       string `json:"kind"`
	Size       int64  `json:"size"`
	Mode       uint32 `json:"mode"`
	ModifiedAt string `json:"modifiedAt"`
	UID        uint32 `json:"uid"`
	GID        uint32 `json:"gid"`
	Symlink    bool   `json:"symlink"`
}

type Info struct {
	Root       string `json:"root"`
	RootLabel  string `json:"rootLabel"`
	User       string `json:"user"`
	ReadOnly   bool   `json:"readOnly"`
	Trash      bool   `json:"trash"`
	PathPolicy string `json:"pathPolicy"`
}

type ReadResult struct {
	Data       string `json:"data"`
	Offset     int64  `json:"offset"`
	Bytes      int    `json:"bytes"`
	EOF        bool   `json:"eof"`
	Size       int64  `json:"size"`
	Mode       uint32 `json:"mode"`
	ModifiedAt string `json:"modifiedAt"`
}

type WriteResult struct {
	Bytes int    `json:"bytes"`
	Size  int64  `json:"size"`
	Mode  uint32 `json:"mode"`
}

type CopyResult struct {
	Bytes int64 `json:"bytes"`
	Files int   `json:"files"`
	Dirs  int   `json:"dirs"`
}

type TrashEntry struct {
	ID           string   `json:"id"`
	StoredName   string   `json:"storedName"`
	OriginalPath []string `json:"originalPath"`
	OriginalName string   `json:"originalName"`
	Kind         string   `json:"kind"`
	Size         int64    `json:"size"`
	Mode         uint32   `json:"mode"`
	DeletedAt    string   `json:"deletedAt"`
}

type Manager struct {
	root     string
	rootFD   int
	userName string
	mu       sync.Mutex
}

func NewManager() (*Manager, error) {
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return nil, coded("FILES_ROOT_UNAVAILABLE")
	}
	name := "linux"
	if current, currentErr := user.Current(); currentErr == nil && current.Username != "" {
		name = current.Username
	}
	return newManagerForRoot(home, name)
}

func NewManagerForRoot(root string) (*Manager, error) {
	return newManagerForRoot(root, "test-user")
}

func newManagerForRoot(root, userName string) (*Manager, error) {
	if !filepath.IsAbs(root) {
		return nil, coded("FILES_ROOT_UNAVAILABLE")
	}
	canonical, err := filepath.EvalSymlinks(root)
	if err != nil {
		return nil, coded("FILES_ROOT_UNAVAILABLE")
	}
	fd, err := syscall.Open(canonical, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_CLOEXEC|syscall.O_NOFOLLOW, 0)
	if err != nil {
		return nil, coded("FILES_ROOT_UNAVAILABLE")
	}
	return &Manager{root: canonical, rootFD: fd, userName: userName}, nil
}

func (m *Manager) Close() {
	if m == nil || m.rootFD < 0 {
		return
	}
	_ = syscall.Close(m.rootFD)
	m.rootFD = -1
}

func (m *Manager) Info() Info {
	return Info{Root: "home", RootLabel: "Linux Home", User: m.userName, ReadOnly: false, Trash: true, PathPolicy: "fd-beneath-no-follow"}
}

func validateSegments(parts []string, internal bool) error {
	if len(parts) > MaxSegments {
		return coded("FILES_PATH_LIMIT")
	}
	for index, part := range parts {
		if part == "" || part == "." || part == ".." || strings.ContainsAny(part, "/\\\x00") || len([]byte(part)) > MaxNameBytes {
			return coded("FILES_PATH_INVALID")
		}
		if !internal && index == 0 && part == trashDirName {
			return coded("FILES_PATH_RESERVED")
		}
	}
	return nil
}

func (m *Manager) dupRoot() (int, error) {
	if m == nil || m.rootFD < 0 {
		return -1, coded("FILES_ROOT_UNAVAILABLE")
	}
	fd, err := syscall.Dup(m.rootFD)
	if err != nil {
		return -1, coded("FILES_OPEN_FAILED")
	}
	return fd, nil
}

func openDirFrom(rootFD int, parts []string) (int, error) {
	fd, err := syscall.Dup(rootFD)
	if err != nil {
		return -1, coded("FILES_OPEN_FAILED")
	}
	for _, part := range parts {
		next, openErr := syscall.Openat(fd, part, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_CLOEXEC|syscall.O_NOFOLLOW, 0)
		_ = syscall.Close(fd)
		if openErr != nil {
			if errors.Is(openErr, syscall.ELOOP) {
				return -1, coded("FILES_SYMLINK_DENIED")
			}
			if errors.Is(openErr, syscall.ENOENT) {
				return -1, coded("FILES_NOT_FOUND")
			}
			if errors.Is(openErr, syscall.EACCES) || errors.Is(openErr, syscall.EPERM) {
				return -1, coded("FILES_PERMISSION_DENIED")
			}
			return -1, coded("FILES_OPEN_FAILED")
		}
		fd = next
	}
	return fd, nil
}

func (m *Manager) openDir(parts []string, internal bool) (int, error) {
	if err := validateSegments(parts, internal); err != nil {
		return -1, err
	}
	return openDirFrom(m.rootFD, parts)
}

func (m *Manager) openParent(parts []string, internal bool) (int, string, error) {
	if len(parts) == 0 {
		return -1, "", coded("FILES_PATH_INVALID")
	}
	if err := validateSegments(parts, internal); err != nil {
		return -1, "", err
	}
	fd, err := openDirFrom(m.rootFD, parts[:len(parts)-1])
	if err != nil {
		return -1, "", err
	}
	return fd, parts[len(parts)-1], nil
}

func fileInfoFromFD(fd int, name, kind string) (Entry, error) {
	var stat syscall.Stat_t
	if err := syscall.Fstat(fd, &stat); err != nil {
		return Entry{}, coded("FILES_STAT_FAILED")
	}
	mode := uint32(stat.Mode & 0o7777)
	modified := time.Unix(stat.Mtim.Sec, stat.Mtim.Nsec).UTC().Format(time.RFC3339Nano)
	return Entry{Name: name, Kind: kind, Size: stat.Size, Mode: mode, ModifiedAt: modified, UID: stat.Uid, GID: stat.Gid}, nil
}

func openChild(parentFD int, name string) (int, string, error) {
	fd, err := syscall.Openat(parentFD, name, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_CLOEXEC|syscall.O_NOFOLLOW, 0)
	if err == nil {
		return fd, "directory", nil
	}
	if errors.Is(err, syscall.ELOOP) {
		return -1, "symlink", coded("FILES_SYMLINK_DENIED")
	}
	fd, err = syscall.Openat(parentFD, name, syscall.O_RDONLY|syscall.O_CLOEXEC|syscall.O_NOFOLLOW|syscall.O_NONBLOCK, 0)
	if err != nil {
		if errors.Is(err, syscall.ELOOP) {
			return -1, "symlink", coded("FILES_SYMLINK_DENIED")
		}
		if errors.Is(err, syscall.ENOENT) {
			return -1, "", coded("FILES_NOT_FOUND")
		}
		if errors.Is(err, syscall.EACCES) || errors.Is(err, syscall.EPERM) {
			return -1, "", coded("FILES_PERMISSION_DENIED")
		}
		return -1, "", coded("FILES_OPEN_FAILED")
	}
	var stat syscall.Stat_t
	if syscall.Fstat(fd, &stat) != nil || stat.Mode&syscall.S_IFMT != syscall.S_IFREG {
		_ = syscall.Close(fd)
		return -1, "other", coded("FILES_TYPE_DENIED")
	}
	return fd, "file", nil
}

func (m *Manager) List(parts []string) ([]Entry, error) {
	fd, err := m.openDir(parts, false)
	if err != nil {
		return nil, err
	}
	file := os.NewFile(uintptr(fd), "cloudos-files-dir")
	if file == nil {
		_ = syscall.Close(fd)
		return nil, coded("FILES_OPEN_FAILED")
	}
	defer file.Close()
	entries, err := file.ReadDir(-1)
	if err != nil {
		return nil, coded("FILES_READ_FAILED")
	}
	out := make([]Entry, 0, len(entries))
	for _, item := range entries {
		name := item.Name()
		if len(parts) == 0 && name == trashDirName {
			continue
		}
		childFD, kind, openErr := openChild(fd, name)
		if openErr != nil {
			if Code(openErr) == "FILES_SYMLINK_DENIED" {
				out = append(out, Entry{Name: name, Kind: "symlink", Symlink: true})
			}
			continue
		}
		entry, statErr := fileInfoFromFD(childFD, name, kind)
		_ = syscall.Close(childFD)
		if statErr == nil {
			out = append(out, entry)
		}
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Kind != out[j].Kind {
			return out[i].Kind == "directory"
		}
		return strings.ToLower(out[i].Name) < strings.ToLower(out[j].Name)
	})
	return out, nil
}

func (m *Manager) Read(parts []string, offset int64, limit int) (ReadResult, error) {
	if offset < 0 {
		return ReadResult{}, coded("FILES_OFFSET_INVALID")
	}
	if limit <= 0 || limit > MaxReadChunk {
		limit = MaxReadChunk
	}
	parentFD, name, err := m.openParent(parts, false)
	if err != nil {
		return ReadResult{}, err
	}
	defer syscall.Close(parentFD)
	fd, err := syscall.Openat(parentFD, name, syscall.O_RDONLY|syscall.O_CLOEXEC|syscall.O_NOFOLLOW, 0)
	if err != nil {
		if errors.Is(err, syscall.ELOOP) {
			return ReadResult{}, coded("FILES_SYMLINK_DENIED")
		}
		if errors.Is(err, syscall.ENOENT) {
			return ReadResult{}, coded("FILES_NOT_FOUND")
		}
		return ReadResult{}, coded("FILES_READ_FAILED")
	}
	defer syscall.Close(fd)
	var stat syscall.Stat_t
	if syscall.Fstat(fd, &stat) != nil || stat.Mode&syscall.S_IFMT != syscall.S_IFREG {
		return ReadResult{}, coded("FILES_TYPE_DENIED")
	}
	buffer := make([]byte, limit)
	n, readErr := syscall.Pread(fd, buffer, offset)
	if readErr != nil {
		return ReadResult{}, coded("FILES_READ_FAILED")
	}
	return ReadResult{Data: base64.StdEncoding.EncodeToString(buffer[:n]), Offset: offset, Bytes: n, EOF: offset+int64(n) >= stat.Size, Size: stat.Size, Mode: uint32(stat.Mode & 0o7777), ModifiedAt: time.Unix(stat.Mtim.Sec, stat.Mtim.Nsec).UTC().Format(time.RFC3339Nano)}, nil
}

func (m *Manager) Write(parts []string, offset int64, dataBase64 string, truncate bool, mode uint32) (WriteResult, error) {
	if offset < 0 {
		return WriteResult{}, coded("FILES_OFFSET_INVALID")
	}
	data, err := base64.StdEncoding.DecodeString(dataBase64)
	if err != nil || len(data) > MaxWriteChunk {
		return WriteResult{}, coded("FILES_IO_INVALID")
	}
	parentFD, name, err := m.openParent(parts, false)
	if err != nil {
		return WriteResult{}, err
	}
	defer syscall.Close(parentFD)
	flags := syscall.O_WRONLY | syscall.O_CREAT | syscall.O_CLOEXEC | syscall.O_NOFOLLOW
	if truncate && offset == 0 {
		flags |= syscall.O_TRUNC
	}
	if mode == 0 || mode > 0o7777 {
		mode = 0o600
	}
	fd, err := syscall.Openat(parentFD, name, flags, mode)
	if err != nil {
		if errors.Is(err, syscall.ELOOP) {
			return WriteResult{}, coded("FILES_SYMLINK_DENIED")
		}
		if errors.Is(err, syscall.EACCES) || errors.Is(err, syscall.EPERM) {
			return WriteResult{}, coded("FILES_PERMISSION_DENIED")
		}
		return WriteResult{}, coded("FILES_WRITE_FAILED")
	}
	defer syscall.Close(fd)
	var stat syscall.Stat_t
	if syscall.Fstat(fd, &stat) != nil || stat.Mode&syscall.S_IFMT != syscall.S_IFREG {
		return WriteResult{}, coded("FILES_TYPE_DENIED")
	}
	n, writeErr := syscall.Pwrite(fd, data, offset)
	if writeErr != nil || n != len(data) {
		return WriteResult{}, coded("FILES_WRITE_FAILED")
	}
	if err := syscall.Fsync(fd); err != nil {
		return WriteResult{}, coded("FILES_WRITE_FAILED")
	}
	if err := syscall.Fstat(fd, &stat); err != nil {
		return WriteResult{}, coded("FILES_STAT_FAILED")
	}
	return WriteResult{Bytes: n, Size: stat.Size, Mode: uint32(stat.Mode & 0o7777)}, nil
}

func (m *Manager) Mkdir(parts []string, mode uint32) error {
	parentFD, name, err := m.openParent(parts, false)
	if err != nil {
		return err
	}
	defer syscall.Close(parentFD)
	if mode == 0 || mode > 0o7777 {
		mode = 0o700
	}
	if err := syscall.Mkdirat(parentFD, name, mode); err != nil {
		if errors.Is(err, syscall.EEXIST) {
			return coded("FILES_ALREADY_EXISTS")
		}
		if errors.Is(err, syscall.EACCES) || errors.Is(err, syscall.EPERM) {
			return coded("FILES_PERMISSION_DENIED")
		}
		return coded("FILES_WRITE_FAILED")
	}
	return nil
}

func existsAt(parentFD int, name string) bool {
	fd, _, err := openChild(parentFD, name)
	if err == nil {
		_ = syscall.Close(fd)
		return true
	}
	return Code(err) == "FILES_SYMLINK_DENIED"
}

func (m *Manager) Rename(source, destination []string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	srcFD, srcName, err := m.openParent(source, false)
	if err != nil {
		return err
	}
	defer syscall.Close(srcFD)
	dstFD, dstName, err := m.openParent(destination, false)
	if err != nil {
		return err
	}
	defer syscall.Close(dstFD)
	if existsAt(dstFD, dstName) {
		return coded("FILES_ALREADY_EXISTS")
	}
	if err := syscall.Renameat(srcFD, srcName, dstFD, dstName); err != nil {
		if errors.Is(err, syscall.EXDEV) {
			return coded("FILES_CROSS_DEVICE")
		}
		if errors.Is(err, syscall.ENOENT) {
			return coded("FILES_NOT_FOUND")
		}
		return coded("FILES_RENAME_FAILED")
	}
	return nil
}

func copyFD(srcFD, dstFD int) (int64, error) {
	sourceDup, err := syscall.Dup(srcFD)
	if err != nil {
		return 0, coded("FILES_COPY_FAILED")
	}
	destinationDup, err := syscall.Dup(dstFD)
	if err != nil {
		_ = syscall.Close(sourceDup)
		return 0, coded("FILES_COPY_FAILED")
	}
	source := os.NewFile(uintptr(sourceDup), "cloudos-copy-src")
	destination := os.NewFile(uintptr(destinationDup), "cloudos-copy-dst")
	if source == nil || destination == nil {
		if source != nil { _ = source.Close() } else { _ = syscall.Close(sourceDup) }
		if destination != nil { _ = destination.Close() } else { _ = syscall.Close(destinationDup) }
		return 0, coded("FILES_COPY_FAILED")
	}
	defer source.Close()
	defer destination.Close()
	written, err := io.CopyBuffer(destination, source, make([]byte, 256*1024))
	if err != nil {
		return written, coded("FILES_COPY_FAILED")
	}
	if err := destination.Sync(); err != nil {
		return written, coded("FILES_COPY_FAILED")
	}
	return written, nil
}

func copyEntry(srcParentFD int, srcName string, dstParentFD int, dstName string, result *CopyResult) error {
	srcFD, kind, err := openChild(srcParentFD, srcName)
	if err != nil {
		return err
	}
	defer syscall.Close(srcFD)
	var stat syscall.Stat_t
	if syscall.Fstat(srcFD, &stat) != nil {
		return coded("FILES_STAT_FAILED")
	}
	mode := uint32(stat.Mode & 0o7777)
	if kind == "file" {
		dstFD, err := syscall.Openat(dstParentFD, dstName, syscall.O_WRONLY|syscall.O_CREAT|syscall.O_EXCL|syscall.O_CLOEXEC|syscall.O_NOFOLLOW, mode)
		if err != nil {
			if errors.Is(err, syscall.EEXIST) {
				return coded("FILES_ALREADY_EXISTS")
			}
			return coded("FILES_COPY_FAILED")
		}
		written, copyErr := copyFD(srcFD, dstFD)
		_ = syscall.Fchmod(dstFD, mode)
		_ = syscall.Close(dstFD)
		if copyErr != nil {
			_ = os.Remove(fmt.Sprintf("/proc/self/fd/%d/%s", dstParentFD, dstName))
			return copyErr
		}
		result.Bytes += written
		result.Files++
		return nil
	}
	if kind != "directory" {
		return coded("FILES_TYPE_DENIED")
	}
	if err := syscall.Mkdirat(dstParentFD, dstName, mode); err != nil {
		if errors.Is(err, syscall.EEXIST) {
			return coded("FILES_ALREADY_EXISTS")
		}
		return coded("FILES_COPY_FAILED")
	}
	dstFD, err := syscall.Openat(dstParentFD, dstName, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_CLOEXEC|syscall.O_NOFOLLOW, 0)
	if err != nil {
		return coded("FILES_COPY_FAILED")
	}
	defer syscall.Close(dstFD)
	sourceDup, err := syscall.Dup(srcFD)
	if err != nil {
		return coded("FILES_COPY_FAILED")
	}
	reader := os.NewFile(uintptr(sourceDup), "cloudos-copy-dir")
	if reader == nil {
		_ = syscall.Close(sourceDup)
		return coded("FILES_COPY_FAILED")
	}
	entries, readErr := reader.ReadDir(-1)
	_ = reader.Close()
	if readErr != nil {
		return coded("FILES_COPY_FAILED")
	}
	result.Dirs++
	for _, child := range entries {
		if child.Type()&os.ModeSymlink != 0 {
			return coded("FILES_SYMLINK_DENIED")
		}
		if err := copyEntry(srcFD, child.Name(), dstFD, child.Name(), result); err != nil {
			return err
		}
	}
	_ = syscall.Fchmod(dstFD, mode)
	return nil
}

func removeEntry(parentFD int, name string) error {
	fd, kind, err := openChild(parentFD, name)
	if err != nil {
		if Code(err) == "FILES_SYMLINK_DENIED" {
			if unlinkErr := syscall.Unlinkat(parentFD, name); unlinkErr != nil {
				return coded("FILES_DELETE_FAILED")
			}
			return nil
		}
		return err
	}
	if kind == "file" {
		_ = syscall.Close(fd)
		if err := syscall.Unlinkat(parentFD, name); err != nil {
			return coded("FILES_DELETE_FAILED")
		}
		return nil
	}
	reader := os.NewFile(uintptr(fd), "cloudos-remove-dir")
	entries, readErr := reader.ReadDir(-1)
	if readErr != nil {
		_ = reader.Close()
		return coded("FILES_DELETE_FAILED")
	}
	for _, child := range entries {
		if err := removeEntry(fd, child.Name()); err != nil {
			_ = reader.Close()
			return err
		}
	}
	_ = reader.Close()
	if err := os.Remove(fmt.Sprintf("/proc/self/fd/%d/%s", parentFD, name)); err != nil {
		return coded("FILES_DELETE_FAILED")
	}
	return nil
}

func (m *Manager) Copy(source, destination []string) (CopyResult, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	srcFD, srcName, err := m.openParent(source, false)
	if err != nil {
		return CopyResult{}, err
	}
	defer syscall.Close(srcFD)
	dstFD, dstName, err := m.openParent(destination, false)
	if err != nil {
		return CopyResult{}, err
	}
	defer syscall.Close(dstFD)
	if existsAt(dstFD, dstName) {
		return CopyResult{}, coded("FILES_ALREADY_EXISTS")
	}
	result := CopyResult{}
	if err := copyEntry(srcFD, srcName, dstFD, dstName, &result); err != nil {
		_ = removeEntry(dstFD, dstName)
		return CopyResult{}, err
	}
	return result, nil
}

func (m *Manager) ensureTrash() (int, error) {
	if err := syscall.Mkdirat(m.rootFD, trashDirName, 0o700); err != nil && !errors.Is(err, syscall.EEXIST) {
		return -1, coded("FILES_TRASH_UNAVAILABLE")
	}
	fd, err := syscall.Openat(m.rootFD, trashDirName, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_CLOEXEC|syscall.O_NOFOLLOW, 0)
	if err != nil {
		return -1, coded("FILES_TRASH_UNAVAILABLE")
	}
	return fd, nil
}

func randomID() string {
	buffer := make([]byte, 12)
	if _, err := rand.Read(buffer); err != nil {
		return fmt.Sprintf("%x", time.Now().UnixNano())
	}
	return hex.EncodeToString(buffer)
}

func writeJSONAt(parentFD int, name string, value any) error {
	data, err := json.Marshal(value)
	if err != nil || len(data) > 64*1024 {
		return coded("FILES_METADATA_FAILED")
	}
	temporary := name + ".tmp-" + randomID()
	fd, err := syscall.Openat(parentFD, temporary, syscall.O_WRONLY|syscall.O_CREAT|syscall.O_EXCL|syscall.O_CLOEXEC|syscall.O_NOFOLLOW, 0o600)
	if err != nil {
		return coded("FILES_METADATA_FAILED")
	}
	file := os.NewFile(uintptr(fd), "cloudos-trash-meta")
	_, writeErr := file.Write(data)
	if writeErr == nil {
		writeErr = file.Sync()
	}
	_ = file.Close()
	if writeErr != nil {
		_ = syscall.Unlinkat(parentFD, temporary)
		return coded("FILES_METADATA_FAILED")
	}
	if err := syscall.Renameat(parentFD, temporary, parentFD, name); err != nil {
		_ = syscall.Unlinkat(parentFD, temporary)
		return coded("FILES_METADATA_FAILED")
	}
	return nil
}

func readTrashMeta(trashFD int, id string) (TrashEntry, error) {
	if len(id) < 8 || len(id) > 64 || strings.ContainsAny(id, "/\\.\x00") {
		return TrashEntry{}, coded("FILES_TRASH_ID_INVALID")
	}
	fd, err := syscall.Openat(trashFD, ".meta-"+id+".json", syscall.O_RDONLY|syscall.O_CLOEXEC|syscall.O_NOFOLLOW, 0)
	if err != nil {
		return TrashEntry{}, coded("FILES_NOT_FOUND")
	}
	file := os.NewFile(uintptr(fd), "cloudos-trash-meta")
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, 64*1024))
	if err != nil {
		return TrashEntry{}, coded("FILES_METADATA_FAILED")
	}
	var meta TrashEntry
	if json.Unmarshal(data, &meta) != nil || meta.ID != id || meta.StoredName == "" || len(meta.OriginalPath) == 0 || validateSegments(meta.OriginalPath, false) != nil {
		return TrashEntry{}, coded("FILES_METADATA_FAILED")
	}
	return meta, nil
}

func statStored(trashFD int, storedName string) (Entry, error) {
	fd, kind, err := openChild(trashFD, storedName)
	if err != nil {
		return Entry{}, err
	}
	defer syscall.Close(fd)
	return fileInfoFromFD(fd, storedName, kind)
}

func (m *Manager) Trash(parts []string) (TrashEntry, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	sourceFD, name, err := m.openParent(parts, false)
	if err != nil {
		return TrashEntry{}, err
	}
	defer syscall.Close(sourceFD)
	checkFD, _, err := openChild(sourceFD, name)
	if err != nil {
		return TrashEntry{}, err
	}
	_ = syscall.Close(checkFD)
	trashFD, err := m.ensureTrash()
	if err != nil {
		return TrashEntry{}, err
	}
	defer syscall.Close(trashFD)
	id := randomID()
	storedName := id + "-item"
	if err := syscall.Renameat(sourceFD, name, trashFD, storedName); err != nil {
		return TrashEntry{}, coded("FILES_TRASH_FAILED")
	}
	stored, err := statStored(trashFD, storedName)
	if err != nil {
		_ = syscall.Renameat(trashFD, storedName, sourceFD, name)
		return TrashEntry{}, err
	}
	meta := TrashEntry{ID: id, StoredName: storedName, OriginalPath: append([]string(nil), parts...), OriginalName: name, Kind: stored.Kind, Size: stored.Size, Mode: stored.Mode, DeletedAt: time.Now().UTC().Format(time.RFC3339Nano)}
	if err := writeJSONAt(trashFD, ".meta-"+id+".json", meta); err != nil {
		_ = syscall.Renameat(trashFD, storedName, sourceFD, name)
		return TrashEntry{}, err
	}
	return meta, nil
}

func (m *Manager) ListTrash() ([]TrashEntry, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	trashFD, err := m.ensureTrash()
	if err != nil {
		return nil, err
	}
	file := os.NewFile(uintptr(trashFD), "cloudos-trash-list")
	if file == nil {
		_ = syscall.Close(trashFD)
		return nil, coded("FILES_TRASH_UNAVAILABLE")
	}
	defer file.Close()
	entries, err := file.ReadDir(-1)
	if err != nil {
		return nil, coded("FILES_TRASH_UNAVAILABLE")
	}
	out := []TrashEntry{}
	for _, entry := range entries {
		name := entry.Name()
		if !strings.HasPrefix(name, ".meta-") || !strings.HasSuffix(name, ".json") {
			continue
		}
		id := strings.TrimSuffix(strings.TrimPrefix(name, ".meta-"), ".json")
		meta, metaErr := readTrashMeta(trashFD, id)
		if metaErr == nil {
			out = append(out, meta)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].DeletedAt > out[j].DeletedAt })
	return out, nil
}

func (m *Manager) Restore(id string) (TrashEntry, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	trashFD, err := m.ensureTrash()
	if err != nil {
		return TrashEntry{}, err
	}
	defer syscall.Close(trashFD)
	meta, err := readTrashMeta(trashFD, id)
	if err != nil {
		return TrashEntry{}, err
	}
	parentParts := meta.OriginalPath[:len(meta.OriginalPath)-1]
	destinationFD, err := m.openDir(parentParts, false)
	if err != nil {
		destinationFD, err = m.dupRoot()
		if err != nil {
			return TrashEntry{}, err
		}
		meta.OriginalPath = []string{meta.OriginalName}
	}
	defer syscall.Close(destinationFD)
	if existsAt(destinationFD, meta.OriginalName) {
		return TrashEntry{}, coded("FILES_ALREADY_EXISTS")
	}
	if err := syscall.Renameat(trashFD, meta.StoredName, destinationFD, meta.OriginalName); err != nil {
		return TrashEntry{}, coded("FILES_RESTORE_FAILED")
	}
	_ = syscall.Unlinkat(trashFD, ".meta-"+id+".json")
	return meta, nil
}

func (m *Manager) DeleteTrash(id string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	trashFD, err := m.ensureTrash()
	if err != nil {
		return err
	}
	defer syscall.Close(trashFD)
	meta, err := readTrashMeta(trashFD, id)
	if err != nil {
		return err
	}
	if err := removeEntry(trashFD, meta.StoredName); err != nil {
		return err
	}
	_ = syscall.Unlinkat(trashFD, ".meta-"+id+".json")
	return nil
}
