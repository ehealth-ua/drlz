defmodule MRS.Mixfile do
  use Mix.Project

  def project do
    [
      app: :drlz,
      version: "0.8.28",
      description: "ESOZ DEC DRLZ SYNC",
      xref: [exclude: [:crypto]],
      package: package(),
      deps: deps()
    ]
  end

  def application do
    [ mod: { DRLZ, [] },
      extra_applications: [ :jsone, :logger, :inets, :ssl, :crypto ]
    ]
  end

  def package do
    [
      files: ~w(lib mix.exs),
      licenses: ["ISC"],
      maintainers: ["Namdak Tonpa"],
      name: :drlz,
      links: %{"GitHub" => "https://github.com/ehealth-ua/drlz"}
    ]
  end

  def deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev},
      {:jsone, "~> 1.5.1"}
    ]
  end

end
