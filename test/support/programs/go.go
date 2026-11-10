package main

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
)

const maxRetries = 3

var ErrEmpty = errors.New("empty line")

type Level int

const (
	LevelInfo Level = iota
	LevelWarn
	LevelError
)

type Entry struct {
	Level   Level
	Message string
}

type ParseError struct {
	Line int
	Err  error
}

func (e *ParseError) Error() string {
	return fmt.Sprintf("line %d: %v", e.Line, e.Err)
}

func (e *ParseError) Unwrap() error { return e.Err }

func parseLevel(word string) (Level, error) {
	switch word {
	case "INFO":
		return LevelInfo, nil
	case "WARN":
		return LevelWarn, nil
	case "ERROR":
		return LevelError, nil
	}
	return 0, fmt.Errorf("bad level %q", word)
}

func parse(n int, line string) (*Entry, error) {
	line = strings.TrimSpace(line)
	if line == "" {
		return nil, ErrEmpty
	}
	head, rest, ok := strings.Cut(line, " ")
	if !ok {
		return nil, &ParseError{Line: n, Err: ErrEmpty}
	}
	level, err := parseLevel(head)
	if err != nil {
		return nil, &ParseError{Line: n, Err: err}
	}
	return &Entry{Level: level, Message: rest}, nil
}

// Deprecated: use load, which skips empty lines.
func loadAll(path string) ([]Entry, error) { return load(path) }

func load(path string) ([]Entry, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var entries []Entry
	for i, line := range strings.Split(string(data), "\n") {
		entry, err := parse(i+1, line)
		if errors.Is(err, ErrEmpty) {
			continue
		}
		if err != nil {
			return nil, err
		}
		entries = append(entries, *entry)
	}
	return entries, nil
}

// ErrLog reports an error the way every caller here does.
func ErrLog(err error) { fmt.Fprintln(os.Stderr, "logscan:", err) }

func each(entries []Entry, visit func(Entry)) {
	for _, e := range entries {
		visit(e)
	}
}

func main() {
	var entries []Entry
	var err error
	for attempt := 0; attempt < maxRetries; attempt++ {
		if entries, err = loadAll("app.log"); err == nil {
			break
		}
	}
	if err != nil {
		var perr *ParseError
		if errors.As(err, &perr) {
			fmt.Fprintln(os.Stderr, "parse failed at line", strconv.Itoa(perr.Line))
		}
		ErrLog(err)
		panic(err)
	}
	counts := map[Level]int{}
	each(entries, func(e Entry) { counts[e.Level]++ })
	fmt.Printf("%v\t%d\n", counts, len(entries))
}
