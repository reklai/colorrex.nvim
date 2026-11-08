class ParseException extends Exception {}
class P {
  int parse(String text) throws ParseException {
    if (text == null) throw new ParseException("empty");
    try { return Integer.parseInt(text); } catch (NumberFormatException err) { throw new ParseException(err.getMessage()); } finally { done = true; }
  }
}
