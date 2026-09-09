// Command greet prints a greeting for the first argument, if any.
package main

import (
	"fmt"
	"os"

	"example.com/hestia-synthetic/greet"
)

func main() {
	name := ""
	if len(os.Args) > 1 {
		name = os.Args[1]
	}
	fmt.Println(greet.Hello(name))
}
