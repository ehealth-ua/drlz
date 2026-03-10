defmodule Medipro do
  require Logger

  def run(input_file, output_file) do
    IO.puts("Converting #{input_file} to #{output_file}...")

    File.write!(output_file, header())

    input_file
    |> File.stream!([:read, :binary], :line)
    |> Stream.map(&:jsone.decode(&1))
    |> Stream.flat_map(&read_product/1)
    |> Stream.chunk_every(100)
    |> Enum.each(fn chunk ->
      File.write!(output_file, Enum.join(chunk), [:append, :raw, :binary])
    end)

    IO.puts("Done.")
  end

  def header do
    "mpid,pmsid,inn_ua,inn_en,language,name,package_pcid,package_status,package_description,package_legal_status\n"
  end

  def read_product(prod) do
    mpid = Map.get(prod, "mpid", "")
    pmsid = Map.get(prod, "pmsid", "")

    inns = Map.get(prod, "inns", [])
    inn_ua = Enum.map_join(inns, "; ", &Map.get(&1, "term_name", ""))
    inn_en = Enum.map_join(inns, "; ", &Map.get(&1, "term_name_en", ""))

    names = Map.get(prod, "names", [])
    packages = Map.get(prod, "packages", [])

    # We want to cross join names and packages for this CSV format
    # OR we can just list names then packages.
    # The user's provided snippet (DRLZ.read("products", prod)) suggests one row per name.
    # Extending to "whole JSON structure" implies we should probably include package info too.
    # To keep it tabular, we'll emit a row for each name-package combination.

    for name_entry <- names, package_entry <- packages do
      name = Map.get(name_entry, "name", "")
      lang = get_v(name_entry, ["language", "term_name"])

      pcid = Map.get(package_entry, "pcid", "")
      status = Map.get(package_entry, "status", "")
      desc = Map.get(package_entry, "description", "")
      legal = get_v(package_entry, ["legalStatusOfSupply", "term_name"])

      "#{fix(mpid)},#{fix(pmsid)},#{fix(inn_ua)},#{fix(inn_en)},#{fix(lang)},#{fix(name)},#{fix(pcid)},#{fix(status)},#{fix(desc)},#{fix(legal)}\n"
    end
  end

  def get_v(:null, _), do: ""
  def get_v(nil, _), do: ""

  def get_v(data, path) do
    case get_in(data, path) do
      :null -> ""
      nil -> ""
      val -> val
    end
  rescue
    _ -> ""
  end

  def fix(:null), do: "\"\""
  def fix(nil), do: "\"\""

  def fix(x) when is_binary(x) do
    escaped = String.replace(x, "\"", "`")
    "\"#{escaped}\""
  end

  def fix(x) do
    "\"#{x}\""
  end
end

# CLI Entry point
case System.argv() do
  [input, output] -> Medipro.run(input, output)
  _ -> IO.puts("Usage: mix run medipro.exs <input.json> <output.csv>")
end
