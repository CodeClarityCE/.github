// Command plugin is a tiny program the central CI builds with the Go image workflow.
package main

import "fmt"

func main() {
fmt.Println( greeting() )
}

func greeting() string {
	return "fixture plugin"
}
