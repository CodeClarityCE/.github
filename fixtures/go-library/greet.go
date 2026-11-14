// Package greet is a tiny module the central CI runs the Go library workflow against.
package greet

// Hello returns a greeting for name.
func Hello(name string) string {
    return "Hello, "+name
}
