package main

import "testing"

func TestGreeting(t *testing.T) {
	if got := greeting(); got != "fixture plugin" {
		t.Fatalf("greeting() = %q", got)
	}
}

// FuzzGreeting gives go-fuzz.yml a target in a main package, where go list stamps VCS info.
func FuzzGreeting(f *testing.F) {
	f.Add("CodeClarity")
	f.Fuzz(func(t *testing.T, _ string) {
		if got := greeting(); got != "fixture plugin" {
			t.Fatalf("greeting() = %q", got)
		}
	})
}
