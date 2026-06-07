package handlers

import (
	"os"
)

// mkdirAllBestEffort creates dir + parents with 0o755 perms. Returns the
// underlying os error, but callers typically ignore it (file persistence
// is non-critical for AI Purchase — it's diagnostic only).
func mkdirAllBestEffort(dir string) error {
	return os.MkdirAll(dir, 0o755)
}

// writeFileBestEffort writes data to path with 0o644 perms.
func writeFileBestEffort(path string, data []byte) error {
	return os.WriteFile(path, data, 0o644)
}
