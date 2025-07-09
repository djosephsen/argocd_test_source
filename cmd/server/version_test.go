package main

import (
	"testing"
)

func TestVersion(t *testing.T) {
	// Version should have some value (either "dev" or actual version)
	if Version == "" {
		t.Errorf("Version should not be empty")
	}
	
	// In test environment, it should default to "dev"
	if Version != "dev" {
		t.Logf("Version is set to: %s", Version)
	}
} 