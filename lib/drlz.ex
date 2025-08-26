defmodule DRLZ do
  use Application
  require Logger
  @page_bulk 100

  def start_link(opt) do {:ok, :erlang.spawn_link(fn -> sync(opt) end)} end
  def child_spec(opt) do %{ id: DRLZ, start: {DRLZ, :start_link, [opt]}, type: :worker, restart: :permanent, shutdown: 5000 } end

  def start(_type, _args) do
      :logger.add_handlers(:drlz)
      children = [ { DRLZ, Date.to_string(Date.utc_today) } ]
      opts = [strategy: :one_for_one, name: DRLZ]
      Supervisor.start_link(children, opts)
  end

  def sync(epoc) do
      sync_dicts(epoc, "/v2/dictionary",                   "dicts", 50)
      sync_table(epoc, "/fhir/ingredients",                "ingredients", 50)
      sync_table(epoc, "/fhir/package-medicinal-products", "packages")
      sync_table(epoc, "/fhir/medicinal-product",          "products")
      sync_table(epoc, "/fhir/substance-definitions",      "substances")
      sync_table(epoc, "/fhir/authorisations",             "licenses")
      sync_table(epoc, "/fhir/manufactured-items",         "forms", 50)
      sync_table(epoc, "/fhir/organization",               "organizations")
  end

  def sync_table(folder, api, name, win \\ @page_bulk) do
      dow = "priv/#{folder}/#{name}.dow"
      csv = "priv/#{folder}/#{name}.csv"
      restart = case :file.read_file(dow) do
         {:ok, bin} -> :erlang.binary_to_integer(bin) + 1
         {:error, _} -> case :file.read_file(csv) do
             {:ok, _} -> :infinity
             {:error, _} -> 1
         end
      end
      pgs = pages(api, win)
      case restart > pgs do
           true -> :file.delete(dow)
           _ ->  Enum.each(restart..pgs, fn y -> case items(api, y, win) do
                 recs when is_list(recs) ->
                      Logger.warn("epoc: [#{folder}], table: [#{name}], page: [#{y}], pages: [#{pgs}], window: [#{length(recs)}]")
                      flat = :lists.foldl(fn x, acc -> acc <> read(name, x) end, "", recs)
                      writeFile(flat, name, folder)
                      :file.write_file(dow, Integer.to_string(y), [:raw, :binary])
                 _ -> Logger.debug("epoc: [#{folder}], table: [#{name}], page: [#{y}], pages: [#{pgs}], window: N/A")
                 end end)
                 :file.delete(dow)
      end
  end

  def sync_dicts(folder, api, name, win \\ @page_bulk) do
      dow = "priv/#{folder}/#{name}.dow"
      csv = "priv/#{folder}/#{name}.csv"
      restart = case :file.read_file(dow) do
         {:ok, bin} -> :erlang.binary_to_integer(bin) + 1
         {:error, _} -> case :file.read_file(csv) do
             {:ok, _} -> :infinity
             {:error, _} -> 1
         end
      end
      %{"total_pages" => pgs, "per_page" => win, "items" => _items} = res(api, win)
      case restart > pgs do
           true -> :file.delete(dow)
           _ -> Enum.each(restart..pgs, fn y ->
                   case items(api, y, win) do
                    recs when is_list(recs) ->
                      flat = :lists.foldl(fn x, acc ->
                        dict = Map.get(x, "dictionary")
                        sync_dict(folder, api, name, win, dict)
                        acc <> read("dicts", x) end, "", recs)
                      Logger.warn("epoc: [#{folder}], table: [#{name}], page: [#{y}], pages: [#{pgs}], window: [#{length(recs)}]")
                      writeFile(flat, name, folder)
                      :file.write_file(dow, Integer.to_string(y), [:raw, :binary])
                 _ -> Logger.debug("epoc: [#{folder}], table: [#{name}], page: [#{y}], pages: [#{pgs}], window: N/A")
                 end end)
                 :file.delete(dow)
      end
  end

  def sync_dict(folder, api, name, win \\ @page_bulk, dict) do
      :filelib.ensure_dir "priv/#{folder}/#{name}/"
      dow = "priv/#{folder}/#{name}/#{dict}.dow"
      csv = "priv/#{folder}/#{name}/#{dict}.csv"
      restart = case :file.read_file(dow) do
         {:ok, bin} -> :erlang.binary_to_integer(bin) + 1
         {:error, _} -> case :file.read_file(csv) do
             {:ok, _} -> :infinity
             {:error, _} -> 1
         end
      end
      versions = versions(api, win, dict)
      vsn = case :lists.foldl(fn x, acc -> case Map.get(x, "list_deactivated_at", 0) do :null -> [x|acc] ; _ -> acc end end, [], versions) do
        [last|_] -> Map.get(last, "version", 1)
        [] -> 1
      end
      pgs = pages_dict(api, win, dict, vsn)
      case restart > pgs do
           true -> :file.delete(dow)
           _ -> Enum.each(restart..pgs, fn y ->
                   case items_dict(api, y, win, dict, vsn) do
                    recs when is_list(recs) ->
                      flat = :lists.foldl(fn x, acc ->
                         acc <> read_dict(x) end, "", recs)
                      Logger.warn("epoc dict: [#{folder}], dict: [#{dict}], vsn: [#{vsn}], page: [#{y}], pages: [#{pgs}], window: [#{length(recs)}]")
                      case y do
                         1 -> writeDict("no,vsn,model,created_on,modified_on,source_term_id,source_vsn,status,item_ua,item_en,item_code,manual,term_short_ua,term_short_en,term_desc\n", name, folder, dict)
                         _ -> :skip
                      end
                      writeDict(flat, name, folder, dict)
                      :file.write_file(dow, Integer.to_string(y), [:raw, :binary])
                 _ -> Logger.debug("epoc dict: [#{folder}], dict: [#{dict}], vsn: [#{vsn}], page: [#{y}], pages: [#{pgs}], window: N/A")
                 end end)
                 :file.delete(dow)
      end
  end

  def res(url,         win \\ @page_bulk) do retrieve(url, win, 1, fn res -> res end) end
  def pages(url,       win \\ @page_bulk) do retrieve(url, win, 1, fn res -> Map.get(res, "pages", 0)  end) end
  def versions(url,    win \\ @page_bulk, dict) do retrieve_dict_versions(url, win, 1, fn res -> Map.get(res, "items", 0)  end, dict) end
  def items(url, page, win \\ @page_bulk) do retrieve(url, win, page, fn res -> Map.get(res, "items", []) end) end
  def items_dict(url, page, win \\ @page_bulk, name, vsn) do retrieve_dict(url, win, page, fn res -> Map.get(res, "items", []) end, name, vsn) end
  def pages_dict(url, win \\ @page_bulk, name, vsn) do retrieve_dict(url, win, 1, fn res -> Map.get(res, "total_pages", 0) end, name, vsn) end

  def retrieve(url, win, page, fun) do
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

  def retrieve_dict_versions(url, win, page, fun, dict) do
      bearer   = :erlang.binary_to_list(:application.get_env(:drlz, :bearer, ""))
      endpoint = :application.get_env(:drlz, :endpoint, "https://drlz.info/api")
      accept   = 'application/json'
      headers  = [{'Authorization','Bearer ' ++ bearer},{'accept',accept}]
      address  = '#{endpoint}#{url}/#{dict}/versions/?page=#{page}&per_page=#{win}'
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

  def retrieve_dict(url, win, page, fun, dict, vsn) do
      bearer   = :erlang.binary_to_list(:application.get_env(:drlz, :bearer, ""))
      endpoint = :application.get_env(:drlz, :endpoint, "https://drlz.info/api")
      accept   = 'application/json'
      headers  = [{'Authorization','Bearer ' ++ bearer},{'accept',accept}]
      address  = '#{endpoint}#{url}/#{dict}/active?dictionary_version=#{vsn}&page=#{page}&per_page=#{win}'
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

  def norm(x) when is_float(x) do
      {i,_} = Integer.parse("#{x}")
      i
  end
  def norm(x) when is_integer(x) do x end
  def norm(x) do x end

  def fix("") do "null" end
  def fix(x) do "\"#{x}\"" end

  def read_dict(dict) do
      no = fix(Map.get(dict, "id", "null"))
      vsn = fix(Map.get(dict, "dictionary_version", "null"))
      model = fix(Map.get(dict, "model", "null"))
      created_on = fix(Map.get(dict, "created_on", "null"))
      modified_on = fix(Map.get(dict, "modified_on", "null"))
      source_term_id = fix(Map.get(dict, "source_term_id", "null"))

      source_vsn = fix(Map.get(dict, "term_source_version", "null"))
      status = fix(Map.get(dict, "term_status", "null"))
      item_ua = Map.get(dict, "term_name", "null")
      term_ua = fix(String.replace(item_ua, "\"", "`"))
      item_en = fix(Map.get(dict, "term_name_en", "null"))
      item_code = fix(Map.get(dict, "term_local_id", "null"))
      manual = fix(Map.get(dict, "is_manually_added", "null"))
      term_short_ua = fix(Map.get(dict, "term_short_name", "null"))
      term_short_en = fix(Map.get(dict, "term_short_name_en", "null"))
      term_desc = String.replace(Map.get(dict, "term_description", "null"), "\n", "")
      term_desc = fix(String.replace(term_desc, "\"", "`"))

      "#{no},#{vsn},#{model},#{created_on},#{modified_on},#{source_term_id},#{source_vsn},#{status},#{item_ua},#{item_en},#{item_code},#{manual},#{term_short_ua},#{term_short_en},#{term_desc}\n"
  end

  def read("dicts", inn) do
      %{"dictionary" => key, "list_name_en" => en, "list_name_ua" => ua, "list_local_version" => vsn, "list_source_id" => id} = inn
      "#{id},#{key},#{en},#{ua},#{vsn},#{}\n"
  end

  def read("version", inn) do
      %{"version" => no, "list_modified_at" => modified, "list_deactivated_at" => deactivated} = inn
      Logger.info "version: #{no}, #{modified}, #{deactivated}"
      inn
  end

  def read("ingredients",inn) do
      %{"for" => references, "pk" => pk, "substance" => %{"coding" => [%{"code" => code, "display" => display, "system" => _system}]}} = inn
      man = Enum.join(Enum.map(references, & &1["reference"]), ",")
      man = String.replace(man, "ManufacturedItemDefinition", "")
      man = String.replace(man, "MedicinalProductDefinition", "")
      "#{pk},#{code},#{display},#{man}\n"
  end

  def read("organizations",company) do
      %{"pk" => pk, "name" => name, "identifier" => ident , "type" => [%{"coding" => [%{"code" => type}]}]} = company
      [%{"display" => disp},%{"code" => code}] = ident
      "#{pk},#{code},#{disp},#{type},#{name}\n"
  end

  def read("substances",molecule) do
      %{"name" => name, "identifier" => [%{"value" => code}]} = molecule
      "#{code},#{name}\n"
  end

  def read("products",prod) do
      %{"pk" => pk, "identifier" => ident, "type" => %{"coding" => [%{"code" => code}]}, "name" => names} = prod
      [%{"value" => license}] = :lists.filter(fn %{"system" => sys} -> sys == "mpid" end, ident)
      Enum.join(:lists.map(fn x -> %{"productName" => name, "usage" => usage } = x
           %{"language" => %{"coding" => [%{"display" => country}]}} = hd(usage)
           "#{pk},#{license},#{code},#{country}-#{name}\n" end, names))
  end

  def read("forms",form) do
      %{"pk" => pk, "ingredient" => ingredients} = form
      Enum.join(:lists.map(fn x -> %{"coding" => [%{"display" => display}]} = x
          "#{pk},#{display}\n" end, ingredients))
  end

  def read("licenses",license) do
      %{"pk" => pk, "identifier" => %{"identifier" => [%{"value" => value}]}, "subject" => [%{"reference" => ref}],
        "validityPeriod" => %{"start" => start, "end" => finish}} = license
      pkg = String.replace(ref,"PackagedProductDefinition","package")
      pkg = String.replace(pkg,"MedicinalProductDefinition","product")
      "#{pk},#{value},#{pkg},#{start},#{finish}\n"
  end

  def read("packages",pkg) do
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

  def writeDict(record, name, folder, dict) do
      :filelib.ensure_dir("priv/#{folder}/#{name}/")
      :file.write_file("priv/#{folder}/#{name}/#{dict}.csv", record, [:append, :raw, :binary])
      record
  end

  def verify(), do: {:ssl, [{:verify, :verify_none}]}

  def unrollPackage([]) do [] end
  def unrollPackage([pkg]) do unrollPackage(pkg) end
  def unrollPackage(%{"containedItem" => item, "packaging" => []}) do item end
  def unrollPackage(%{"packaging" => packaging}) do unrollPackage(hd(packaging)) end

end
