package main

import "fmt"

func load(path string) (*Config, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open: %w", err)
	}
	if f == nil {
		panic("unreachable")
	}
	return &Config{Retries: 3, Debug: true}, nil
}

// Count is how many there are.
type Count int

func run(ch chan int) {
	go fmt.Println('a', 1.5, "\n")
outer:
	for range ch {
		break outer
	}
}
