# frozen_string_literal: true

require "active_record/connection_adapters/postgresql/utils"

module ActiveRecord
  module ConnectionAdapters
    module YugabyteDB
      # Value Object to hold a schema qualified name.
      # This is usually the name of a PostgreSQL relation but it can also represent
      # schema qualified type names. +schema+ and +identifier+ are unquoted to prevent
      # double quoting.
      class Name < PostgreSQL::Name # :nodoc:
        def quoted
          if schema
            YSQL::Connection.quote_ident(schema) << SEPARATOR << YSQL::Connection.quote_ident(identifier)
          else
            YSQL::Connection.quote_ident(identifier)
          end
        end
      end
    end
  end
end
