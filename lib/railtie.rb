# frozen_string_literal: true

module YugabyteDB
  if defined?(Rails::Railtie)
    class Railtie < Rails::Railtie
      railtie_name :yugabytedb

      if Rails.gem_version >= Gem::Version.new("7.2.0.alpha")
        initializer "yugabytedb.register_yugabytedb_adapter", before: "active_record.initialize_database" do
          ActiveRecord::ConnectionAdapters.register(
            "yugabytedb",
            "ActiveRecord::ConnectionAdapters::YugabyteDBAdapter",
            "active_record/connection_adapters/yugabytedb_adapter",
          )
        end
      end

      if ActiveRecord::DatabaseConfigurations.respond_to?(:register_db_config_handler)
        ActiveRecord::DatabaseConfigurations.register_db_config_handler do |env_name, name, url, config|
          next unless config[:adapter] == "yugabytedb"
          
          ActiveRecord::DatabaseConfigurations::YugabyteDBConfig.new(env_name, name, config)
        end
      end

      ActiveRecord::Tasks::DatabaseTasks.register_task(/yugabytedb/, ActiveRecord::Tasks::PostgreSQLDatabaseTasks)
    end
  end
end
