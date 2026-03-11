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
    "mpid,pmsid,inn_ua,inn_en,atc_code,reg_num,exp_date,language,name,package_pcid,package_status,package_description,package_legal_status,release_form,manufactured_dose_form,manufacturer,package_qty\n"
  end

  def read_product(prod) do
    mpid = Map.get(prod, "mpid", "")
    pmsid = Map.get(prod, "pmsid", "")

    inns = Map.get(prod, "inns", [])
    inn_ua = Enum.map_join(inns, "; ", &Map.get(&1, "term_name", ""))
    inn_en = Enum.map_join(inns, "; ", &Map.get(&1, "term_name_en", ""))

    atc_code = Enum.join(Map.get(prod, "atc", []), "; ")
    reg_num = get_v(prod, ["authorisation", "number"])
    exp_date = get_v(prod, ["authorisation", "validityPeriod", "end"])

    names = Map.get(prod, "names", [])
    packages = Map.get(prod, "packages", [])

    for name_entry <- names, package_entry <- packages do
      name = Map.get(name_entry, "name", "")
      lang = get_v(name_entry, ["language", "term_name"])

      pcid = Map.get(package_entry, "pcid", "")
      status = Map.get(package_entry, "status", "")
      desc = Map.get(package_entry, "description", "")
      legal = get_v(package_entry, ["legalStatusOfSupply", "term_name"])

      # Extract items and manufacturers (taking the first one for simplicity if multiple)
      items = flatten_items(Map.get(package_entry, "packageItemContainer", []))

      {release_form, package_qty} =
        case items do
          [item | _] ->
            form = get_v(item, ["manufacturedDoseForm", "term_name"])
            qty_val = get_v(item, ["count", "value"])
            qty_unit = get_v(item, ["count", "unit"])
            {form, "#{qty_val} #{qty_unit}"}

          [] ->
            {"", ""}
        end

      manufacturers = Map.get(package_entry, "manufacturers", [])

      manufacturer =
        case manufacturers do
          [m | _] -> Map.get(m, "name", "")
          [] -> ""
        end

      "#{fix(mpid)},#{fix(pmsid)},#{fix(inn_ua)},#{fix(inn_en)},#{fix(atc_code)},#{fix(reg_num)},#{fix(exp_date)}," <>
        "#{fix(lang)},#{fix(name)},#{fix(pcid)},#{fix(status)},#{fix(desc)},#{fix(legal)}," <>
        "#{fix(release_form)},#{fix(release_form)},#{fix(manufacturer)},#{fix(package_qty)}\n"
    end
  end

  defp flatten_items([]), do: []

  defp flatten_items(containers) when is_list(containers) do
    Enum.flat_map(containers, fn c ->
      items = Map.get(c, "manufacturedItems", [])
      children = Map.get(c, "children", [])
      items ++ flatten_items(children)
    end)
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
