defmodule ZebraPay.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/vinnAnony/zebrapay"

  def project do
    [
      app: :zebrapay,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],

      # Hex
      description: description(),
      package: package(),
      docs: docs(),
      name: "ZebraPay"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {ZebraPay.Application, []}
    ]
  end

  defp deps do
    [
      # HTTP Client
      {:req, "~> 0.5"},

      # JSON
      {:jason, "~> 1.4"},

      # Plug — only needed if you use ZebraPay.WebhookPlug; host Phoenix
      # apps already have it, declared here so the library compiles standalone
      {:plug, "~> 1.16"},

      # Config management
      {:dotenvy, "~> 0.8", only: [:dev, :test]},

      # Testing
      {:ex_machina, "~> 2.7", only: :test},
      {:bypass, "~> 2.1", only: :test},
      {:cowlib, "~> 2.13.0", override: true},
      {:cowboy, "~> 2.10.0", override: true},
      {:mox, "~> 1.1", only: :test},
      {:excoveralls, "~> 0.18", only: :test},

      # Docs
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      "test.all": ["test --cover"],
      lint: ["credo --strict", "dialyzer"],
      setup: ["deps.get", "compile"]
    ]
  end

  defp description do
    """
    ZebraPay — A unified Elixir library for Kenyan and African payment gateways.
    Currently supports M-Pesa (Daraja 3.0) in full: STK Push, B2C, B2B,
    Transaction Status, and Reversal. More gateways coming. Built to scale
    from Kenya to global.
    """
  end

  defp package do
    [
      maintainers: ["Vinn Njeru"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "ZebraPay",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        Core: [ZebraPay, ZebraPay.Config, ZebraPay.Response],
        Gateways: [
          ZebraPay.Gateways.Mpesa
        ],
        Behaviours: [ZebraPay.Gateway, ZebraPay.Webhook],
        Utilities: [ZebraPay.HTTP, ZebraPay.Utils.Crypto, ZebraPay.Utils.Phone]
      ]
    ]
  end
end
