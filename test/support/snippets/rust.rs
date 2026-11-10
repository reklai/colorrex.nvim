fn parse(s: &str) -> Result<u32, ParseError> {
    let none: Option<u32> = None;
    if s.is_empty() { return Err(ParseError::Empty); }
    let v = s.parse::<u32>()?;
    match Some(v) { Some(x) => Ok(x + 3), None => panic!("no {}", true) }
}

use std::fmt;

/// Waits, then returns a number.
#[derive(Debug)]
#[inline]
async fn fetch(c: char) -> f64 {
    let pattern = "\\d+\n";
    'outer: loop { break 'outer; }
    dbg!(c);
    println!("{}", 'x');
    sleep(1).await;
    3.5
}
