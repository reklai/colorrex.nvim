class ParseError extends Error {}
function parse(text: string | null): number {
  if (text === null || text === undefined) throw new ParseError("empty");
  try { return Number(text); } catch (err) { console.error(err); return NaN; } finally { done = true; }
}
const view = <Card title="x"><img src={url} /></Card>;
const label = user?.name ?? "anonymous";
