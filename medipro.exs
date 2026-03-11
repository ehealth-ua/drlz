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
    "mpid,pmsid,inn_ua,inn_en,atc_code,reg_num,exp_date,name_ua,name_en,package_pcid,package_status,package_description,package_legal_status,release_form,manufactured_dose_form_id,manufacturer,package_qty\n"
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
    name_ua = Enum.find_value(names, "", fn n -> if get_v(n, ["language", "term_name"]) == "Українська", do: Map.get(n, "name", "") end)
    name_en = Enum.find_value(names, "", fn n -> if get_v(n, ["language", "term_name"]) == "Англійська", do: Map.get(n, "name", "") end)

    packages = Map.get(prod, "packages", [])

    for package_entry <- packages do
      pcid = Map.get(package_entry, "pcid", "")
      status = Map.get(package_entry, "status", "")
      desc = Map.get(package_entry, "description", "")
      legal = get_v(package_entry, ["legalStatusOfSupply", "term_name"])

      # Extract items and manufacturers (taking the first one for simplicity if multiple)
      items = flatten_items(Map.get(package_entry, "packageItemContainer", []))

      {release_form, dose_form_id, package_qty} =
        case items do
          [item | _] ->
            form = get_v(item, ["manufacturedDoseForm", "term_name"])
            id = get_v(item, ["manufacturedDoseForm", "id"])
            qty_val = get_v(item, ["count", "value"])
            qty_unit = get_v(item, ["count", "unit"])
            {form, id, "#{qty_val} #{qty_unit}"}

          [] ->
            {"", "", ""}
        end

      manufacturers = Map.get(package_entry, "manufacturers", [])

      manufacturer =
        case manufacturers do
          [m | _] -> Map.get(m, "name", "")
          [] -> ""
        end

      "#{fix(mpid)},#{fix(pmsid)},#{fix(inn_ua)},#{fix(inn_en)},#{fix(atc_code)},#{fix(reg_num)},#{fix(exp_date)}," <>
        "#{fix(name_ua)},#{fix(name_en)},#{fix(pcid)},#{fix(status)},#{fix(desc)},#{fix(legal)}," <>
        "#{fix(release_form)},#{fix(dose_form_id)},#{fix(manufacturer)},#{fix(package_qty)}\n"
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
    sanitized = x |> String.trim() |> String.replace(~r/[\r\n]+/, " ")
    escaped = String.replace(sanitized, "\"", "`")
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
