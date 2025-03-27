# frozen_string_literal: true

require "active_record/connection_adapters/postgresql/type_metadata"

module ActiveRecord
  # :stopdoc:
  module ConnectionAdapters
    module YugabyteDB
      class TypeMetadata < PostgreSQL::TypeMetadata
      end
    end
    YugabyteDBTypeMetadata = YugabyteDB::TypeMetadata
  end
end
