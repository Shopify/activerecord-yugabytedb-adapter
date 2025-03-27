# frozen_string_literal: true

gem "yugabytedb-ysql", "~> 0.3"
require "ysql"

require_relative "../../arel/visitors/yugabytedb"
require "active_record/connection_adapters/postgresql_adapter"
require "active_record/connection_adapters/statement_pool"
require "active_record/connection_adapters/yugabytedb/schema_statements"
require "active_record/connection_adapters/yugabytedb/database_statements"
require "active_record/connection_adapters/yugabytedb/oid"
require "active_record/connection_adapters/yugabytedb/type_metadata"
require "active_record/connection_adapters/yugabytedb/utils"

module ActiveRecord
  module ConnectionHandling # :nodoc:
    if Rails.gem_version < Gem::Version.new("7.2.0.alpha")
      # Establishes a connection to the database that's used by all Active Record objects
      def yugabytedb_connection(config)
        ConnectionAdapters::YugabyteDBAdapter.new(config)
      end
    end
  end

  module ConnectionAdapters
    # = Active Record YugabyteDB Adapter
    #
    # The PostgreSQL adapter works with the native C (https://github.com/ged/ruby-pg) driver.
    #
    # Options:
    #
    # * <tt>:host</tt> - Defaults to a Unix-domain socket in /tmp. On machines without Unix-domain sockets,
    #   the default is to connect to localhost.
    # * <tt>:port</tt> - Defaults to 5432.
    # * <tt>:username</tt> - Defaults to be the same as the operating system name of the user running the application.
    # * <tt>:password</tt> - Password to be used if the server demands password authentication.
    # * <tt>:database</tt> - Defaults to be the same as the username.
    # * <tt>:schema_search_path</tt> - An optional schema search path for the connection given
    #   as a string of comma-separated schema names. This is backward-compatible with the <tt>:schema_order</tt> option.
    # * <tt>:encoding</tt> - An optional client encoding that is used in a <tt>SET client_encoding TO
    #   <encoding></tt> call on the connection.
    # * <tt>:min_messages</tt> - An optional client min messages that is used in a
    #   <tt>SET client_min_messages TO <min_messages></tt> call on the connection.
    # * <tt>:variables</tt> - An optional hash of additional parameters that
    #   will be used in <tt>SET SESSION key = val</tt> calls on the connection.
    # * <tt>:insert_returning</tt> - An optional boolean to control the use of <tt>RETURNING</tt> for <tt>INSERT</tt> statements
    #   defaults to true.
    #
    # Any further options are used as connection parameters to libpq. See
    # https://www.postgresql.org/docs/current/static/libpq-connect.html for the
    # list of parameters.
    #
    # In addition, default connection parameters of libpq can be set per environment variables.
    # See https://www.postgresql.org/docs/current/static/libpq-envars.html .
    class YugabyteDBAdapter < PostgreSQLAdapter
      ADAPTER_NAME = "YugabyteDB"

      class << self
        def new_client(conn_params)
          YSQL.connect(**conn_params)
        rescue ::YSQL::Error => error
          if conn_params && conn_params[:dbname] == "postgres"
            raise ActiveRecord::ConnectionNotEstablished, error.message
          elsif conn_params && conn_params[:dbname] && error.message.include?(conn_params[:dbname])
            raise ActiveRecord::NoDatabaseError.db_error(conn_params[:dbname])
          elsif conn_params && conn_params[:user] && error.message.include?(conn_params[:user])
            raise ActiveRecord::DatabaseConnectionError.username_error(conn_params[:user])
          elsif conn_params && conn_params[:host] && error.message.include?(conn_params[:host])
            raise ActiveRecord::DatabaseConnectionError.hostname_error(conn_params[:host])
          else
            raise ActiveRecord::ConnectionNotEstablished, error.message
          end
        end
      end

      include YugabyteDB::SchemaStatements
      include YugabyteDB::DatabaseStatements

      class StatementPool < ConnectionAdapters::StatementPool # :nodoc:
        def initialize(connection, max)
          super(max)
          @connection = connection
          @counter = 0
        end

        def next_key
          "a#{@counter += 1}"
        end

        private
          def dealloc(key)
            # This is ugly, but safe: the statement pool is only
            # accessed while holding the connection's lock. (And we
            # don't need the complication of with_raw_connection because
            # a reconnect would invalidate the entire statement pool.)
            if conn = @connection.instance_variable_get(:@raw_connection)
              conn.query "DEALLOCATE #{key}" if conn.status == YSQL::CONNECTION_OK
            end
          rescue YSQL::Error
          end
      end

      # Initializes and connects a YugabyteDB adapter.
      def initialize(...)
        super

        conn_params = @config.compact

        # Map ActiveRecords param names to PGs.
        conn_params[:user] = conn_params.delete(:username) if conn_params[:username]
        conn_params[:dbname] = conn_params.delete(:database) if conn_params[:database]

        # Forward only valid config params to YSQL::Connection.connect.
        valid_conn_param_keys = YSQL::Connection.conndefaults_hash.keys + [:requiressl]
        conn_params.slice!(*valid_conn_param_keys)

        @connection_parameters = conn_params

        @max_identifier_length = nil
        @type_map = nil
        @raw_connection = nil
        @notice_receiver_sql_warnings = []

        @use_insert_returning = @config.key?(:insert_returning) ? self.class.type_cast_config_to_boolean(@config[:insert_returning]) : true
      end

      def reset!
        @lock.synchronize do
          return connect! unless @raw_connection

          unless @raw_connection.transaction_status == ::YSQL::PQTRANS_IDLE
            @raw_connection.query "ROLLBACK"
          end
          @raw_connection.query "DISCARD ALL"

          super
        end
      end

      def supports_ddl_transactions?
        false
      end

      def supports_advisory_locks?
        false
      end

      def check_version # :nodoc:
        if database_version < 9_03_00 # < 9.3
          raise "Your version of YugabyteDB (#{database_version}) is too old. Active Record supports YugabyteDB >= 9.3."
        end
      end

      private

        def translate_exception(exception, message:, sql:, binds:)
          return exception unless exception.respond_to?(:result)

          case exception.result.try(:error_field, YSQL::PG_DIAG_SQLSTATE)
          when nil
            if exception.message.match?(/connection is closed/i)
              ConnectionNotEstablished.new(exception, connection_pool: @pool)
            elsif exception.is_a?(YSQL::ConnectionBad)
              # libpq message style always ends with a newline; the pg gem's internal
              # errors do not. We separate these cases because a pg-internal
              # ConnectionBad means it failed before it managed to send the query,
              # whereas a libpq failure could have occurred at any time (meaning the
              # server may have already executed part or all of the query).
              if exception.message.end_with?("\n")
                ConnectionFailed.new(exception, connection_pool: @pool)
              else
                ConnectionNotEstablished.new(exception, connection_pool: @pool)
              end
            else
              super
            end
          when UNIQUE_VIOLATION
            RecordNotUnique.new(message, sql: sql, binds: binds, connection_pool: @pool)
          when FOREIGN_KEY_VIOLATION
            InvalidForeignKey.new(message, sql: sql, binds: binds, connection_pool: @pool)
          when VALUE_LIMIT_VIOLATION
            ValueTooLong.new(message, sql: sql, binds: binds, connection_pool: @pool)
          when NUMERIC_VALUE_OUT_OF_RANGE
            RangeError.new(message, sql: sql, binds: binds, connection_pool: @pool)
          when NOT_NULL_VIOLATION
            NotNullViolation.new(message, sql: sql, binds: binds, connection_pool: @pool)
          when SERIALIZATION_FAILURE
            SerializationFailure.new(message, sql: sql, binds: binds, connection_pool: @pool)
          when DEADLOCK_DETECTED
            Deadlocked.new(message, sql: sql, binds: binds, connection_pool: @pool)
          when DUPLICATE_DATABASE
            DatabaseAlreadyExists.new(message, sql: sql, binds: binds, connection_pool: @pool)
          when LOCK_NOT_AVAILABLE
            LockWaitTimeout.new(message, sql: sql, binds: binds, connection_pool: @pool)
          when QUERY_CANCELED
            QueryCanceled.new(message, sql: sql, binds: binds, connection_pool: @pool)
          else
            super
          end
        end

        def retryable_query_error?(exception)
          # We cannot retry anything if we're inside a broken transaction; we need to at
          # least raise until the innermost savepoint is rolled back
          @raw_connection&.transaction_status != ::YSQL::PQTRANS_INERROR &&
            super
        end

        # Annoyingly, the code for prepared statements whose return value may
        # have changed is FEATURE_NOT_SUPPORTED.
        #
        # This covers various different error types so we need to do additional
        # work to classify the exception definitively as a
        # ActiveRecord::PreparedStatementCacheExpired
        #
        # Check here for more details:
        # https://git.postgresql.org/gitweb/?p=postgresql.git;a=blob;f=src/backend/utils/cache/plancache.c#l573
        def is_cached_plan_failure?(e)
          pgerror = e.cause
          pgerror.result.result_error_field(YSQL::PG_DIAG_SQLSTATE) == FEATURE_NOT_SUPPORTED &&
            pgerror.result.result_error_field(YSQL::PG_DIAG_SOURCE_FUNCTION) == "RevalidateCachedQuery"
        rescue
          false
        end

        def reconnect
          begin
            @raw_connection&.reset
          rescue YSQL::ConnectionBad
            @raw_connection = nil
          end

          connect unless @raw_connection
        end

        # Configures the encoding, verbosity, schema search path, and time zone of the connection.
        # This is called by #connect and should not be called manually.
        def configure_connection
          if @config[:encoding]
            @raw_connection.set_client_encoding(@config[:encoding])
          end
          self.client_min_messages = @config[:min_messages] || "warning"
          self.schema_search_path = @config[:schema_search_path] || @config[:schema_order]

          unless ActiveRecord.db_warnings_action.nil?
            @raw_connection.set_notice_receiver do |result|
              message = result.error_field(YSQL::Result::PG_DIAG_MESSAGE_PRIMARY)
              code = result.error_field(YSQL::Result::PG_DIAG_SQLSTATE)
              level = result.error_field(YSQL::Result::PG_DIAG_SEVERITY)
              @notice_receiver_sql_warnings << SQLWarning.new(message, code, level, nil, @pool)
            end
          end

          # Use standard-conforming strings so we don't have to do the E'...' dance.
          set_standard_conforming_strings

          variables = @config.fetch(:variables, {}).stringify_keys

          # Set interval output format to ISO 8601 for ease of parsing by ActiveSupport::Duration.parse
          internal_execute("SET intervalstyle = iso_8601")

          # SET statements from :variables config hash
          # https://www.postgresql.org/docs/current/static/sql-set.html
          variables.map do |k, v|
            if v == ":default" || v == :default
              # Sets the value to the global or compile default
              internal_execute("SET SESSION #{k} TO DEFAULT")
            elsif !v.nil?
              internal_execute("SET SESSION #{k} TO #{quote(v)}")
            end
          end

          add_pg_encoders
          add_pg_decoders

          reload_type_map
        end

        def arel_visitor
          Arel::Visitors::YugabyteDB.new(self)
        end

        def add_pg_encoders
          map = YSQL::TypeMapByClass.new
          map[Integer] = YSQL::TextEncoder::Integer.new
          map[TrueClass] = YSQL::TextEncoder::Boolean.new
          map[FalseClass] = YSQL::TextEncoder::Boolean.new
          @raw_connection.type_map_for_queries = map
        end

        def update_typemap_for_default_timezone
          if @raw_connection && @mapped_default_timezone != default_timezone && @timestamp_decoder
            decoder_class = default_timezone == :utc ?
                              YSQL::TextDecoder::TimestampUtc :
                              YSQL::TextDecoder::TimestampWithoutTimeZone

            @timestamp_decoder = decoder_class.new(**@timestamp_decoder.to_h)
            @raw_connection.type_map_for_results.add_coder(@timestamp_decoder)

            @mapped_default_timezone = default_timezone

            # if default timezone has changed, we need to reconfigure the connection
            # (specifically, the session time zone)
            reconfigure_connection_timezone

            true
          end
        end

        def add_pg_decoders
          @mapped_default_timezone = nil
          @timestamp_decoder = nil

          coders_by_name = {
            "int2" => YSQL::TextDecoder::Integer,
            "int4" => YSQL::TextDecoder::Integer,
            "int8" => YSQL::TextDecoder::Integer,
            "oid" => YSQL::TextDecoder::Integer,
            "float4" => YSQL::TextDecoder::Float,
            "float8" => YSQL::TextDecoder::Float,
            "numeric" => YSQL::TextDecoder::Numeric,
            "bool" => YSQL::TextDecoder::Boolean,
            "timestamp" => YSQL::TextDecoder::TimestampUtc,
            "timestamptz" => YSQL::TextDecoder::TimestampWithTimeZone,
          }

          known_coder_types = coders_by_name.keys.map { |n| quote(n) }
          query = <<~SQL % known_coder_types.join(", ")
            SELECT t.oid, t.typname
            FROM pg_type as t
            WHERE t.typname IN (%s)
          SQL
          result = internal_execute(query, "SCHEMA", [], allow_retry: true, materialize_transactions: false)
          coders = result.filter_map { |row| construct_coder(row, coders_by_name[row["typname"]]) }

          map = YSQL::TypeMapByOid.new
          coders.each { |coder| map.add_coder(coder) }
          @raw_connection.type_map_for_results = map

          @type_map_for_results = YSQL::TypeMapByOid.new
          @type_map_for_results.default_type_map = map
          @type_map_for_results.add_coder(YSQL::TextDecoder::Bytea.new(oid: 17, name: "bytea"))
          @type_map_for_results.add_coder(MoneyDecoder.new(oid: 790, name: "money"))

          # extract timestamp decoder for use in update_typemap_for_default_timezone
          @timestamp_decoder = coders.find { |coder| coder.name == "timestamp" }
          update_typemap_for_default_timezone
        end

        class MoneyDecoder < YSQL::SimpleDecoder # :nodoc:
          TYPE = YugabyteDB::OID::Money.new

          def decode(value, tuple = nil, field = nil)
            TYPE.deserialize(value)
          end
        end

        ActiveRecord::Type.add_modifier({ array: true }, YugabyteDB::OID::Array, adapter: :yugabytedb)
        ActiveRecord::Type.add_modifier({ range: true }, YugabyteDB::OID::Range, adapter: :yugabytedb)
        ActiveRecord::Type.register(:bit, YugabyteDB::OID::Bit, adapter: :yugabytedb)
        ActiveRecord::Type.register(:bit_varying, YugabyteDB::OID::BitVarying, adapter: :yugabytedb)
        ActiveRecord::Type.register(:binary, YugabyteDB::OID::Bytea, adapter: :yugabytedb)
        ActiveRecord::Type.register(:cidr, YugabyteDB::OID::Cidr, adapter: :yugabytedb)
        ActiveRecord::Type.register(:date, YugabyteDB::OID::Date, adapter: :yugabytedb)
        ActiveRecord::Type.register(:datetime, YugabyteDB::OID::DateTime, adapter: :yugabytedb)
        ActiveRecord::Type.register(:decimal, YugabyteDB::OID::Decimal, adapter: :yugabytedb)
        ActiveRecord::Type.register(:enum, YugabyteDB::OID::Enum, adapter: :yugabytedb)
        ActiveRecord::Type.register(:hstore, YugabyteDB::OID::Hstore, adapter: :yugabytedb)
        ActiveRecord::Type.register(:inet, YugabyteDB::OID::Inet, adapter: :yugabytedb)
        ActiveRecord::Type.register(:interval, YugabyteDB::OID::Interval, adapter: :yugabytedb)
        ActiveRecord::Type.register(:jsonb, YugabyteDB::OID::Jsonb, adapter: :yugabytedb)
        ActiveRecord::Type.register(:money, YugabyteDB::OID::Money, adapter: :yugabytedb)
        ActiveRecord::Type.register(:point, YugabyteDB::OID::Point, adapter: :yugabytedb)
        ActiveRecord::Type.register(:legacy_point, YugabyteDB::OID::LegacyPoint, adapter: :yugabytedb)
        ActiveRecord::Type.register(:uuid, YugabyteDB::OID::Uuid, adapter: :yugabytedb)
        ActiveRecord::Type.register(:vector, YugabyteDB::OID::Vector, adapter: :yugabytedb)
        ActiveRecord::Type.register(:xml, YugabyteDB::OID::Xml, adapter: :yugabytedb)
    end

    ActiveSupport.run_load_hooks(:active_record_yugabytedbadapter, YugabyteDBAdapter)
  end
end
