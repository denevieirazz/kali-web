package main

import (
	"fmt"
	"os"

	"github.com/denevieirazz/kali-web/core/wsl/cloudos-core/internal/server"
)

func main() {
	options := server.Options{}
	switch {
	case len(os.Args) == 2 && os.Args[1] == "serve":
	case len(os.Args) == 3 && os.Args[1] == "serve" && os.Args[2] == "--cgroup-control":
		options.CgroupControl = true
	default:
		fmt.Fprintln(os.Stderr, "usage: cloudos-core serve [--cgroup-control]")
		os.Exit(2)
	}
	if err := server.RunWithOptions(os.Stdin, os.Stdout, os.Stderr, options); err != nil {
		fmt.Fprintln(os.Stderr, "cloudos-core: service unavailable")
		os.Exit(1)
	}
}
