# frozen_string_literal: true

require "active_record/database_configurations"

module ActiveRecord
  class DatabaseConfigurations
    class YugabyteDBConfig < HashConfig
      attr_reader :load_balance, :topology_keys

      def initialize(env_name, name, configuration_hash = {})
        super
        yugabytedb = configuration_hash.delete(:yugabytedb)
        @load_balance = yugabytedb[:load_balance]
        @topology_keys = yugabytedb[:topology_keys]

        @configuration_hash = configuration_hash.merge(**yugabytedb.symbolize_keys)
      end
    end
  end
end
