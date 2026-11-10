class ParseError < StandardError; end
def parse(text)
  raise ParseError, "empty" if text.nil? || text == nil
  Integer(text)
rescue ArgumentError => err
  fail ParseError, err.message
ensure
  @done = true
end
options = { name: "x", retries: 3, mode: :fast }
