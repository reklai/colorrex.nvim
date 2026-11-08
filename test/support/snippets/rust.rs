fn parse(s: &str) -> Result<u32, ParseError> {
    let none: Option<u32> = None;
    if s.is_empty() { return Err(ParseError::Empty); }
    let v = s.parse::<u32>()?;
    match Some(v) { Some(x) => Ok(x + 3), None => panic!("no {}", true) }
}
