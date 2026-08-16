package metrics

import "testing"

func TestReadRealProcMetrics(t *testing.T) {
	snapshot, err := Read()
	if err != nil {
		t.Fatal(err)
	}
	if snapshot.UptimeSeconds <= 0 {
		t.Fatalf("invalid uptime: %v", snapshot.UptimeSeconds)
	}
	if snapshot.Memory.TotalBytes == 0 {
		t.Fatal("missing memory total")
	}
	if snapshot.ProcessCount <= 0 {
		t.Fatal("missing process count")
	}
}
