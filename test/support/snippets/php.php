<?php
class ParseException extends Exception {}
function parse($text) {
  if ($text === null) throw new ParseException("empty");
  try { return intval($text); } catch (ValueError $err) { throw $err; } finally { $done = true; }
}
