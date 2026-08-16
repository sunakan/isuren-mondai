package main

import "testing"

func TestPowerDNSRecordName(t *testing.T) {
	t.Parallel()

	const username = "test-user"
	want := username + ".u.isuren.internal"
	if got := powerDNSRecordName(username); got != want {
		t.Fatalf("powerDNSRecordName(%q) = %q, want %q", username, got, want)
	}
}
