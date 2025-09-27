module CacheSweeper
  class Railtie < Rails::Railtie
    initializer "cache_sweeper.configure_defaults" do
      CacheSweeper.configure_defaults
    end

    config.after_initialize do
      CacheSweeper::Loader.load_sweepers!
      CacheSweeper::Loader.hook_sweepers!
    end
  end
end