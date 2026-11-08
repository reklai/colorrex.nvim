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
