defmodule P do
  def parse(text) do
    case Integer.parse(text) do
      {n, ""} -> {:ok, n}
      :error -> {:error, :invalid}
    end
  rescue
    err in ArgumentError -> raise ParseError, message: "bad"
  end
  def check(nil), do: raise("empty")
  def ready, do: true
end
