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
