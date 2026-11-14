package main

import "testing"

func TestGreeting(t *testing.T) {
	if got := greeting(); got != "fixture plugin" {
		t.Fatalf("greeting() = %q", got)
	}
}
