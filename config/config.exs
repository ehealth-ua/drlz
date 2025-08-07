import Config

config :drlz,
  load_on_start: false,
  bearer: System.get_env("DRLZ"),
  logger_level: :info,
  logger: [{:handler, :default2, :logger_std_h,
            %{level: :debug,
              id: :synrc,
              max_size: 2000,
              module: :logger_std_h,
              config: %{type: :file, file: 'drlz.log'},
              formatter: {:logger_formatter,
                          %{template: [:time,' ',:pid,' ',:module,' ',:msg,'\n'],
                            single_line: true,}}}}]

