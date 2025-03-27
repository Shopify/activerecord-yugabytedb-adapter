# frozen_string_literal: true

module YugabyteDB
end

require "active_record/database_configurations"
require "active_record/database_configurations/yugabyte_db_config"
require "railtie" if defined?(Rails::Railtie)