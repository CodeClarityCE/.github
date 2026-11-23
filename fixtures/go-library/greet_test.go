package greet

import "testing"

func TestHello(t *testing.T) {
	if got := Hello("CodeClarity"); got != "Hello, CodeClarity" {
		t.Fatalf("Hello() = %q", got)
	}
}

// FuzzHello gives go-fuzz.yml a target to find and run.
func FuzzHello(f *testing.F) {
	f.Add("CodeClarity")
	f.Fuzz(func(t *testing.T, name string) {
		if got := Hello(name); got != "Hello, "+name {
			t.Fatalf("Hello(%q) = %q", name, got)
		}
	})
}
