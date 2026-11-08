class ParseException : Exception {}
class P {
  int Parse(string text) {
    if (text == null) throw new ParseException("empty");
    try { return int.Parse(text); } catch (FormatException err) { throw; } finally { done = true; }
  }
}
