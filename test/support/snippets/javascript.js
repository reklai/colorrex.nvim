class ParseError extends Error {}
function parse(text) {
  if (text === null || text === undefined) throw new ParseError("empty");
  try { return Number(text); } catch (err) { console.error(err); return NaN; } finally { done = true; }
}
