pub fn parse(text: String) -> Result(Int, ParseError) {
  case int.parse(text) {
    Ok(n) -> Ok(n + 3)
    Error(Nil) -> Error(Empty)
  }
}
pub fn must(x) {
  let assert Ok(v) = x
  panic as "no"
}
fn later() { todo }
