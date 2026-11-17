# frozen_string_literal: true

module CacheSweeper
  class Railtie < Rails::Railtie
    initializer "cache_sweeper.defaults", before: :load_config_initializers do
      CacheSweeper.config.raise_errors = Rails.env.local?
    end

    initializer "cache_sweeper.log_subscriber" do
      CacheSweeper::LogSubscriber.attach_to :cache_sweeper
    end

    initializer "cache_sweeper.executor" do |app|
      app.executor.register_hook(CacheSweeper::ExecutorHook)
    end

    initializer "cache_sweeper.reloader" do |app|
      app.reloader.before_class_unload { CacheSweeper.registry.clear }
    end

    config.to_prepare do
      CacheSweeper.config.sweeper_paths.each do |path|
        directory = Rails.root.join(path)
        Rails.autoloaders.main.eager_load_dir(directory) if directory.directory?
      end
    end
  end
end
