package files

import (
	"encoding/base64"
	"os"
	"path/filepath"
	"testing"
)

func newTestManager(t *testing.T) (*Manager, string) {
	t.Helper()
	root := t.TempDir()
	manager, err := NewManagerForRoot(root)
	if err != nil {
		t.Fatalf("NewManagerForRoot: %v", err)
	}
	t.Cleanup(manager.Close)
	return manager, root
}

func writeData(t *testing.T, manager *Manager, parts []string, text string, mode uint32) {
	t.Helper()
	_, err := manager.Write(parts, 0, base64.StdEncoding.EncodeToString([]byte(text)), true, mode)
	if err != nil {
		t.Fatalf("Write(%v): %v", parts, err)
	}
}

func TestTraversalAndReservedPathsAreRejected(t *testing.T) {
	manager, _ := newTestManager(t)
	for _, parts := range [][]string{{".."}, {"a/b"}, {"a\\b"}, {trashDirName, "x"}} {
		if _, err := manager.List(parts); err == nil {
			t.Fatalf("expected path rejection for %#v", parts)
		}
	}
}

func TestSymlinkCannotEscapeRoot(t *testing.T) {
	manager, root := newTestManager(t)
	outside := t.TempDir()
	outsideSecret := filepath.Join(outside, "secret.txt")
	outsideNew := filepath.Join(outside, "new.txt")
	if err := os.WriteFile(outsideSecret, []byte("outside"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(root, "escape")); err != nil {
		t.Skipf("symlink unavailable: %v", err)
	}
	if _, err := manager.List([]string{"escape"}); err == nil {
		t.Fatal("listing through an escaped symlink unexpectedly succeeded")
	}
	if _, err := manager.Read([]string{"escape", "secret.txt"}, 0, 1024); err == nil {
		t.Fatal("reading through an escaped symlink unexpectedly succeeded")
	}
	if _, err := manager.Write([]string{"escape", "new.txt"}, 0, base64.StdEncoding.EncodeToString([]byte("bad")), true, 0o600); err == nil {
		t.Fatal("writing through an escaped symlink unexpectedly succeeded")
	}
	data, err := os.ReadFile(outsideSecret)
	if err != nil || string(data) != "outside" {
		t.Fatalf("outside source changed: %q %v", data, err)
	}
	if _, err := os.Stat(outsideNew); !os.IsNotExist(err) {
		t.Fatalf("escaped write created a file outside the root: %v", err)
	}
}

func TestListReadWriteAndCopyPreserveMode(t *testing.T) {
	manager, root := newTestManager(t)
	if err := manager.Mkdir([]string{"docs"}, 0o750); err != nil {
		t.Fatal(err)
	}
	writeData(t, manager, []string{"docs", "note.txt"}, "hello cloudos", 0o640)

	entries, err := manager.List([]string{"docs"})
	if err != nil || len(entries) != 1 {
		t.Fatalf("List: %#v %v", entries, err)
	}
	if entries[0].Name != "note.txt" || entries[0].Kind != "file" || entries[0].Mode != 0o640 {
		t.Fatalf("unexpected entry: %#v", entries[0])
	}
	read, err := manager.Read([]string{"docs", "note.txt"}, 0, 1024)
	if err != nil {
		t.Fatal(err)
	}
	decoded, _ := base64.StdEncoding.DecodeString(read.Data)
	if string(decoded) != "hello cloudos" || !read.EOF {
		t.Fatalf("unexpected read: %q eof=%v", decoded, read.EOF)
	}

	result, err := manager.Copy([]string{"docs", "note.txt"}, []string{"docs", "copy.txt"})
	if err != nil || result.Files != 1 || result.Bytes != int64(len("hello cloudos")) {
		t.Fatalf("Copy: %#v %v", result, err)
	}
	info, err := os.Stat(filepath.Join(root, "docs", "copy.txt"))
	if err != nil {
		t.Fatal(err)
	}
	if uint32(info.Mode().Perm()) != 0o640 {
		t.Fatalf("mode not preserved: %o", info.Mode().Perm())
	}
}

func TestDirectoryCopyRejectsSymlinkAndRollsBackDestination(t *testing.T) {
	manager, root := newTestManager(t)
	if err := manager.Mkdir([]string{"src"}, 0o750); err != nil {
		t.Fatal(err)
	}
	writeData(t, manager, []string{"src", "ok.txt"}, "ok", 0o600)
	if err := os.Symlink("/tmp", filepath.Join(root, "src", "escape")); err != nil {
		t.Skipf("symlink unavailable: %v", err)
	}
	if _, err := manager.Copy([]string{"src"}, []string{"dst"}); Code(err) != "FILES_SYMLINK_DENIED" {
		t.Fatalf("expected symlink rejection, got %v (%s)", err, Code(err))
	}
	if _, err := os.Stat(filepath.Join(root, "dst")); !os.IsNotExist(err) {
		t.Fatalf("partial destination was not rolled back: %v", err)
	}
}

func TestTrashAndRestoreAreSameFilesystemRenames(t *testing.T) {
	manager, root := newTestManager(t)
	if err := manager.Mkdir([]string{"work"}, 0o750); err != nil {
		t.Fatal(err)
	}
	writeData(t, manager, []string{"work", "rollback.txt"}, "transaction", 0o640)
	trashed, err := manager.Trash([]string{"work", "rollback.txt"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(root, "work", "rollback.txt")); !os.IsNotExist(err) {
		t.Fatalf("source still exists after trash: %v", err)
	}
	trash, err := manager.ListTrash()
	if err != nil || len(trash) != 1 || trash[0].ID != trashed.ID {
		t.Fatalf("ListTrash: %#v %v", trash, err)
	}
	if _, err := manager.Restore(trashed.ID); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(filepath.Join(root, "work", "rollback.txt"))
	if err != nil {
		t.Fatal(err)
	}
	if uint32(info.Mode().Perm()) != 0o640 {
		t.Fatalf("restore changed mode: %o", info.Mode().Perm())
	}
}

func TestPermanentTrashDeleteDoesNotTouchOutsideSymlinkTarget(t *testing.T) {
	manager, root := newTestManager(t)
	outside := t.TempDir()
	outsideFile := filepath.Join(outside, "keep.txt")
	if err := os.WriteFile(outsideFile, []byte("keep"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outsideFile, filepath.Join(root, "link")); err != nil {
		t.Skipf("symlink unavailable: %v", err)
	}
	if _, err := manager.Trash([]string{"link"}); Code(err) != "FILES_SYMLINK_DENIED" {
		t.Fatalf("symlink should not enter transactional trash: %v (%s)", err, Code(err))
	}
	if data, err := os.ReadFile(outsideFile); err != nil || string(data) != "keep" {
		t.Fatalf("outside target changed: %q %v", data, err)
	}
}
