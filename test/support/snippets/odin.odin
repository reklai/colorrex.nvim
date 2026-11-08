parse :: proc(text: string) -> (n: int, err: Parse_Error) {
	if text == "" do return 0, .Empty
	v := strconv.parse_int(text) or_return
	p: ^int = nil
	if p == nil do panic("open")
	return v + 3, nil
}
