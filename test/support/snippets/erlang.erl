parse(Text) ->
    case catch list_to_integer(Text) of
        {'EXIT', _} -> {error, badarg};
        N -> {ok, N + 3}
    end.
check(undefined) -> erlang:error(empty);
check(_) -> throw(nope), true.
