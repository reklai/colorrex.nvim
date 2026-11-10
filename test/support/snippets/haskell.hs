parse :: String -> Either ParseError Int
parse "" = Left Empty
parse s = case readMaybe s of
  Nothing -> error "bad"
  Just n -> Right (n + 3)
must x = maybe undefined id x
size m = fromMaybe 0 m + fromJust m
