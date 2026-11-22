package greet

import (
	"net"
	"os"
	"testing"
	"time"
)

// TestCIProvidesServices checks go-checks.yml gives tests Postgres and RabbitMQ.
func TestCIProvidesServices(t *testing.T) {
	for name, addr := range map[string]string{
		"postgres": net.JoinHostPort(os.Getenv("PG_DB_HOST"), os.Getenv("PG_DB_PORT")),
		"rabbitmq": net.JoinHostPort(os.Getenv("AMQP_HOST"), os.Getenv("AMQP_PORT")),
	} {
		conn, err := net.DialTimeout("tcp", addr, 5*time.Second)
		if err != nil {
			if os.Getenv("CI") == "" {
				t.Skipf("%s unreachable at %s outside CI: %v", name, addr, err)
			}
			t.Fatalf("%s unreachable at %s in CI: %v", name, addr, err)
		}
		conn.Close()
	}
}
