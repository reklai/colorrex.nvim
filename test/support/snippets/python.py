class ParseError(Exception):
    pass
def parse(text):
    if text is None:
        raise ParseError("empty")
    try:
        return int(text), True
    except ValueError as err:
        raise ParseError(str(err)) from err
    finally:
        print(__name__, 3)
import os
from dataclasses import dataclass

@dataclass
class Point:
    """A point on the grid."""
    x: float = 0.5

    @staticmethod
    def origin():
        return Point()

type Pair = tuple[int, int]

async def fetch(*args, key=None):
    await os.sleep(1)
    if key and not args or key in args:
        return f"{args!r}\n"
