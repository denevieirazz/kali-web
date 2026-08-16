package main

import (
	"fmt"
	"os"

	"github.com/denevieirazz/kali-web/core/wsl/cloudos-core/internal/server"
)

func main() {
	if len(os.Args) != 2 || os.Args[1] != "serve" {
		fmt.Fprintln(os.Stderr, "usage: cloudos-core serve")
		os.Exit(2)
	}
	if err := server.Run(os.Stdin, os.Stdout, os.Stderr); err != nil {
		fmt.Fprintln(os.Stderr, "cloudos-core: service unavailable")
		os.Exit(1)
	}
}
