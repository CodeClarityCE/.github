package greet

import "testing"

func TestHello(t *testing.T) {
	if got := Hello("CodeClarity"); got != "Hello, CodeClarity" {
		t.Fatalf("Hello() = %q", got)
	}
}
