defmodule DRLZ do
  use Application
  require Logger
  @page_bulk 100

  def start_link(opt) do {:ok, :erlang.spawn_link(fn -> sync(opt) end)} end
  def child_spec(opt) do %{ id: DRLZ, start: {DRLZ, :start_link, [opt]}, type: :worker, restart: :permanent, shutdown: 500 } end

  def start(_type, _args) do
      :logger.add_handlers(:drlz)
      children = [ { DRLZ, Date.to_string(Date.utc_today) } ]
      opts = [strategy: :one_for_one, name: DRLZ]
      Supervisor.start_link(children, opts)
  end

  def sync(folder) do
      sync_table(folder, "/fhir/ingredients",                "ingredients")
      sync_table(folder, "/fhir/package-medicinal-products", "packages")
      sync_table(folder, "/fhir/medicinal-product",          "products")
      sync_table(folder, "/fhir/substance-definitions",      "substances")
      sync_table(folder, "/fhir/authorisations",             "licenses")
      sync_table(folder, "/fhir/manufactured-items",         "forms")
      sync_table(folder, "/fhir/organization",               "organizations")
  end

  def sync_table(folder, api, name, win \\ @page_bulk) do
      restart = case :file.read_file("priv/#{folder}/#{name}.dow") do
         {:ok, bin} -> :erlang.binary_to_integer(bin) + 1
         {:error, _} -> 1
      end
      pgs = pages(api, win)
      case restart > pgs do
           true -> :skip
           _ ->  Enum.each(restart..pgs, fn y -> case items(api, y, win) do
                 recs when is_list(recs) ->
                      Logger.warn("epoc: [#{folder}], table: [#{name}], page: [#{y}], pages: [#{pgs}], window: [#{length(recs)}]")
                      flat = :lists.foldl(fn x, acc -> acc <> xform(name, x) end, "", recs)
                      writeFile(flat, name, folder)
                      :file.write_file("priv/#{folder}/#{name}.dow", Integer.to_string(y), [:raw, :binary])
                 _ -> Logger.debug("epoc: [#{folder}], table: [#{name}], page: [#{y}], pages: [#{pgs}], window: N/A")
           end end)
      end
  end

  def pages(url,       win \\ @page_bulk) do retrive(url, win, 1,    fn res -> Map.get(res, "pages", 0)  end) end
  def items(url, page, win \\ @page_bulk) do retrive(url, win, page, fn res -> Map.get(res, "items", []) end) end

  def retrive(url, win, page, fun) do
      bearer   = :erlang.binary_to_list(:application.get_env(:drlz, :bearer, ""))
      endpoint = :application.get_env(:drlz, :endpoint, "https://drlz.info/api")
      accept   = 'application/json'
      headers  = [{'Authorization','Bearer ' ++ bearer},{'accept',accept}]
      address  = '#{endpoint}#{url}?page=#{page}&limit=#{win}'
      case :httpc.request(:get, {address, headers}, [{:timeout,:application.get_env(:drlz,:timeout,100000)},verify()], [{:body_format,:binary}]) do
         {:ok,{{_,status,_},_headers,body}} ->
             case status do
             _ when status >= 100 and status < 200 -> Logger.error("WebSockets not supported: #{body}") ; 0
             _ when status >= 500 and status < 600 -> Logger.error("Fatal Error: #{body}") ; 0
             _ when status >= 400 and status < 500 -> Logger.error("Resource not available: #{address}") ; 0
             _ when status >= 300 and status < 400 -> Logger.error("Go away: #{body}") ; 0
             _ when status >= 200 and status < 300 -> fun.(:jsone.decode(body)) end
         {:error,reason} ->
             Logger.error("Network Error: #{:io_lib.format('~p',[reason])}")
             raise "Network Error" # crash
      end
  end

  def xform("ingredients", x)   do readIngredient(x) end
  def xform("organizations", x) do readOrganization(x) end
  def xform("substances", x)    do readSubstance(x) end
  def xform("products", x)      do readProduct(x) end
  def xform("forms", x)         do readForm(x) end
  def xform("licenses", x)      do readLicense(x) end
  def xform("packages", x)      do readPackage(x) end

  def readIngredient(inn) do
      %{"for" => references, "pk" => pk, "substance" => %{"coding" => [%{"code" => code, "display" => display, "system" => _system}]}} = inn
      man = Enum.join(Enum.map(references, & &1["reference"]), ",")
      man = String.replace(man, "ManufacturedItemDefinition", "")
      man = String.replace(man, "MedicinalProductDefinition", "")
      "#{pk},#{code},#{display},#{man}\n"
  end

  def readOrganization(company) do
      %{"pk" => pk, "name" => name, "identifier" => ident , "type" => [%{"coding" => [%{"code" => type}]}]} = company
      [%{"display" => disp},%{"code" => code}] = ident
      "#{pk},#{code},#{disp},#{type},#{name}\n"
  end

  def readSubstance(molecule) do
      %{"name" => name, "identifier" => [%{"value" => code}]} = molecule
      "#{code},#{name}\n"
  end

  def readProduct(prod) do
      %{"pk" => pk, "identifier" => ident, "type" => %{"coding" => [%{"code" => code}]}, "name" => names} = prod
      [%{"value" => license}] = :lists.filter(fn %{"system" => sys} -> sys == "mpid" end, ident)
      Enum.join(:lists.map(fn x -> %{"productName" => name, "usage" => usage } = x
           %{"language" => %{"coding" => [%{"display" => country}]}} = hd(usage)
           "#{pk},#{license},#{code},#{country}-#{name}\n" end, names))
  end

  def readForm(form) do
      %{"pk" => pk, "ingredient" => ingredients} = form
      Enum.join(:lists.map(fn x -> %{"coding" => [%{"display" => display}]} = x
          "#{pk},#{display}\n" end, ingredients))
  end

  def readLicense(license) do
      %{"pk" => pk, "identifier" => %{"identifier" => [%{"value" => value}]}, "subject" => [%{"reference" => ref}],
        "validityPeriod" => %{"start" => start, "end" => finish}} = license
      pkg = String.replace(ref,"PackagedProductDefinition","package")
      pkg = String.replace(pkg,"MedicinalProductDefinition","product")
      "#{pk},#{value},#{pkg},#{start},#{finish}\n"
  end

  def readPackage(pkg) do
      %{"pk" => pk,  "manufacturer" => manu_list, "packageFor" => [%{"reference" => product}], "packaging" => packaging} = pkg
      manu = case manu_list do
         [] -> ""
         mlist ->
           %{"manufacturer" => %{"reference" => r}} = hd(mlist)
           r
      end
      prod = String.replace(product, "MedicinalProductDefinition", "")
      man  = String.replace(manu, "Organization", "")
      form = :lists.foldl(fn x,acc ->
           case unrollPackage(x) do [] -> acc
                 [item|_] -> %{"item" => %{"reference" => reference}} = item
                             [_,f] = String.split(reference,"/")
                             f
           end end, "", packaging)
      "#{pk},#{prod},#{form},#{man}\n"
  end

  def writeFile(record, name, folder) do
      :filelib.ensure_dir("priv/#{folder}/")
      :file.write_file("priv/#{folder}/#{name}.csv", record, [:append, :raw, :binary])
      record
  end

  def verify(), do: {:ssl, [{:verify, :verify_none}]}

  def unrollPackage([]) do [] end
  def unrollPackage([pkg]) do unrollPackage(pkg) end
  def unrollPackage(%{"containedItem" => item, "packaging" => []}) do item end
  def unrollPackage(%{"packaging" => packaging}) do unrollPackage(hd(packaging)) end

end
