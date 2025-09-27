module CacheSweeper
  class Railtie < Rails::Railtie
    initializer "cache_sweeper.configure_defaults" do
      CacheSweeper.configure_defaults
    end

    # Ensure sweepers are attached after code reload in dev
    config.to_prepare do
      CacheSweeper::Loader.ensure_attached
    end
  end
end