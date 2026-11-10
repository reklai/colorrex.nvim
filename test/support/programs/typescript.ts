const MAX_RETRIES = 3;

enum Level {
  Info = "INFO",
  Warn = "WARN",
  Error = "ERROR",
}

interface Entry {
  readonly level: Level;
  message: string;
}

class ParseError extends Error {
  constructor(public readonly line: number, reason: string) {
    super(`line ${line}: ${reason}`);
    this.name = "ParseError";
  }
}

namespace Text {
  export const SEPARATOR = " ";

  export function words(line: string): string[] {
    return line.trim().split(SEPARATOR);
  }
}

function parseLevel(word: string): Level | undefined {
  return Object.values(Level).find((level) => level === word);
}

export function parse(n: number, raw: string): Entry | null {
  const [head, ...rest] = Text.words(raw);
  if (head === "") {
    return null;
  }
  const level = parseLevel(head);
  if (level === undefined) {
    throw new ParseError(n, `bad level ${head}`);
  }
  return { level, message: rest.join(Text.SEPARATOR) };
}

class Log {
  private entries: Entry[] = [];
  static loaded = 0;

  async load(url: string): Promise<number> {
    const response = await fetch(url);
    const text = await response.text();
    for (const [i, raw] of text.split("\n").entries()) {
      const entry = parse(i + 1, raw);
      if (entry !== null) {
        this.entries.push(entry);
      }
    }
    Log.loaded += 1;
    return this.entries.length;
  }

  firstSerious(): Entry | undefined {
    return this.entries.find((e) => e.level !== Level.Info);
  }

  /** @deprecated use firstSerious */
  first(): Entry | undefined {
    return this.entries[0];
  }
}

function each(entries: readonly Entry[], visit: (entry: Entry) => void): void {
  for (const entry of entries) {
    visit(entry);
  }
}

async function main(url: string): Promise<void> {
  const log = new Log();
  let attempts = 0;
  let lastError: unknown = null;
  while (attempts < MAX_RETRIES) {
    attempts++;
    try {
      await log.load(url);
      lastError = null;
      break;
    } catch (err) {
      lastError = err;
      console.error(`retry ${attempts}`, err instanceof ParseError ? err.line : err);
    }
  }
  if (lastError !== null) {
    throw lastError;
  }
  const serious = log.firstSerious();
  if (!serious) {
    console.log("nothing serious", log.first()?.message);
    return;
  }
  console.log(serious.message, Log.loaded, Math.max(attempts, 1));
}

void main(location.href);
