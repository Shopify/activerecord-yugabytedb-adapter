# frozen_string_literal: true

require "active_record/database_configurations"

module ActiveRecord
  class DatabaseConfigurations
    class YugabyteDBConfig < HashConfig
      # Specific options:
      # - load_balance
      # - topology_keys
      # - yb_servers_refresh_interval
      # - fallback_to_topology_keys_only
      # - failed_host_reconnect_delay_secs

      def initialize(env_name, name, configuration_hash = {})
        yugabytedb = configuration_hash.delete(:yugabytedb)&.symbolize_keys || {}
        super

        @configuration_hash = configuration_hash.merge(**yugabytedb).symbolize_keys.freeze
      end

      def load_balance?
        @configuration_hash["load_balance"]
      end

      def topology_keys
        @configuration_hash["topology_keys"]
      end

      def yb_servers_refresh_interval
        @configuration_hash["yb_servers_refresh_interval"]
      end

      def fallback_to_topology_keys_only
        @configuration_hash["fallback_to_topology_keys_only"]
      end

      def failed_host_reconnect_delay_secs
        @configuration_hash["failed_host_reconnect_delay_secs"]
      end
    end
  end
end