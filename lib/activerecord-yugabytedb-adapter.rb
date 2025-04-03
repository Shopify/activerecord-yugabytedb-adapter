if defined?(Rails::Railtie)
  module ActiveRecord
    module ConnectionAdapters
      class YugabyteDBRailtie < ::Rails::Railtie
        rake_tasks do
          load "active_record/connection_adapters/yugabytedb/database_tasks.rb"
        end

        if Rails.gem_version >= Gem::Version.new("7.2.0.alpha")
          initializer "yugabytedb.register_yugabytedb_adapter", before: "active_record.initialize_database" do
            ActiveRecord::ConnectionAdapters.register(
              "yugabytedb",
              "ActiveRecord::ConnectionAdapters::YugabyteDBAdapter",
              "active_record/connection_adapters/yugabytedb_adapter",
            )
          end
        end

        require "active_record/database_configurations"
          
        if ActiveRecord::DatabaseConfigurations.respond_to?(:register_db_config_handler)
          require "active_record/database_configurations/yugabyte_db_config"

          ActiveRecord::DatabaseConfigurations.register_db_config_handler do |env_name, name, url, config|
            next unless config[:adapter] == "yugabytedb"

            ActiveRecord::DatabaseConfigurations::YugabyteDBConfig.new(env_name, name, config)
          end
        end
      end
    end
  end
end