use std::collections::HashMap;
use std::fmt;
use std::fs;

const MAX_RETRIES: u32 = 3;
static mut LOADS: u32 = 0;

#[derive(Debug, Clone, PartialEq)]
enum Level {
    Info,
    Warn,
    Error,
}

#[derive(Debug)]
enum ParseError {
    Empty,
    BadLevel(String),
    Io(std::io::Error),
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ParseError::Empty => write!(f, "empty line"),
            ParseError::BadLevel(word) => write!(f, "bad level: {}", word),
            ParseError::Io(err) => write!(f, "io: {}", err),
        }
    }
}

impl From<std::io::Error> for ParseError {
    fn from(err: std::io::Error) -> Self {
        ParseError::Io(err)
    }
}

struct Entry {
    level: Level,
    message: String,
}

impl Entry {
    fn parse(line: &str) -> Result<Entry, ParseError> {
        let line = line.trim();
        if line.is_empty() {
            return Err(ParseError::Empty);
        }
        let (head, rest) = line.split_once(' ').ok_or(ParseError::Empty)?;
        let level = match head {
            "INFO" => Level::Info,
            "WARN" => Level::Warn,
            "ERROR" => Level::Error,
            other => return Err(ParseError::BadLevel(other.to_string())),
        };
        Ok(Entry { level, message: rest.to_owned() })
    }

    fn is_serious(&self) -> bool {
        self.level != Level::Info
    }

    fn into_message(self) -> String {
        self.message
    }
}

#[deprecated(note = "callers should look for any serious entry")]
fn first_error(entries: &[Entry]) -> Option<&Entry> {
    entries.iter().find(|entry| entry.level == Level::Error)
}

fn load(path: &str) -> Result<Vec<Entry>, ParseError> {
    let text = fs::read_to_string(path)?;
    let mut entries = Vec::new();
    for line in text.split('\n') {
        match Entry::parse(line) {
            Ok(entry) => entries.push(entry),
            Err(ParseError::Empty) => continue,
            Err(err) => return Err(err),
        }
    }
    unsafe { LOADS += 1 };
    Ok(entries)
}

#[allow(deprecated)]
fn main() {
    let mut counts: HashMap<String, usize> = HashMap::new();
    let mut attempts = 0;
    let entries = loop {
        attempts += 1;
        match load("app.log") {
            Ok(found) => break found,
            Err(err) if attempts < MAX_RETRIES => eprintln!("retry {}: {}", attempts, err),
            Err(err) => panic!("giving up: {}", err),
        }
    };
    for entry in &entries {
        if !entry.is_serious() {
            continue;
        }
        *counts.entry(format!("{:?}", entry.level)).or_insert(0) += 1;
    }
    match first_error(&entries) {
        Some(entry) => println!("first error: {}\n", entry.message),
        None => println!("no errors"),
    }
    let messages: Vec<String> = entries.into_iter().map(Entry::into_message).collect();
    let first = unsafe { messages.as_ptr().as_ref() };
    println!("{:?} {:?} {}", counts, first.map(|m| m.len()), unsafe { LOADS });
}
