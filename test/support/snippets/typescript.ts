class ParseError extends Error {}
function parse(text: string | null): number {
  if (text === null || text === undefined) throw new ParseError("empty");
  try { return Number(text); } catch (err) { console.error(err); return NaN; } finally { done = true; }
}
const label = user?.name ?? "anonymous";
const id = user!.id;
const re = /\d+/g;
