// Package greet is the synthetic fixture library exercised by the fixture build/test.
package greet

import "fmt"

// Hello returns a greeting for name, defaulting to "world" when empty.
func Hello(name string) string {
	if name == "" {
		name = "world"
	}
	return fmt.Sprintf("Hello, %s!", name)
}
