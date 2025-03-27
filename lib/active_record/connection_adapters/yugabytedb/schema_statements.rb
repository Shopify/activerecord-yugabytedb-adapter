# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module YugabyteDB
      module SchemaStatements
        # Returns the sequence name for a table's primary key or some other specified key.
        def default_sequence_name(table_name, pk = "id") # :nodoc:
          result = serial_sequence(table_name, pk)
          return nil unless result
          Utils.extract_schema_qualified_name(result).to_s
        rescue ActiveRecord::StatementInvalid
          YugabyteDB::Name.new(nil, "#{table_name}_#{pk}_seq").to_s
        end

        # Returns a table's primary key and belonging sequence.
        def pk_and_sequence_for(table) # :nodoc:
          # First try looking for a sequence with a dependency on the
          # given table's primary key.
          result = query(<<~SQL, "SCHEMA")[0]
            SELECT attr.attname, nsp.nspname, seq.relname
            FROM pg_class      seq,
                 pg_attribute  attr,
                 pg_depend     dep,
                 pg_constraint cons,
                 pg_namespace  nsp
            WHERE seq.oid           = dep.objid
              AND seq.relkind       = 'S'
              AND attr.attrelid     = dep.refobjid
              AND attr.attnum       = dep.refobjsubid
              AND attr.attrelid     = cons.conrelid
              AND attr.attnum       = cons.conkey[1]
              AND seq.relnamespace  = nsp.oid
              AND cons.contype      = 'p'
              AND dep.classid       = 'pg_class'::regclass
              AND dep.refobjid      = #{quote(quote_table_name(table))}::regclass
          SQL

          if result.nil? || result.empty?
            result = query(<<~SQL, "SCHEMA")[0]
              SELECT attr.attname, nsp.nspname,
                CASE
                  WHEN pg_get_expr(def.adbin, def.adrelid) !~* 'nextval' THEN NULL
                  WHEN split_part(pg_get_expr(def.adbin, def.adrelid), '''', 2) ~ '.' THEN
                    substr(split_part(pg_get_expr(def.adbin, def.adrelid), '''', 2),
                           strpos(split_part(pg_get_expr(def.adbin, def.adrelid), '''', 2), '.')+1)
                  ELSE split_part(pg_get_expr(def.adbin, def.adrelid), '''', 2)
                END
              FROM pg_class       t
              JOIN pg_attribute   attr ON (t.oid = attrelid)
              JOIN pg_attrdef     def  ON (adrelid = attrelid AND adnum = attnum)
              JOIN pg_constraint  cons ON (conrelid = adrelid AND adnum = conkey[1])
              JOIN pg_namespace   nsp  ON (t.relnamespace = nsp.oid)
              WHERE t.oid = #{quote(quote_table_name(table))}::regclass
                AND cons.contype = 'p'
                AND pg_get_expr(def.adbin, def.adrelid) ~* 'nextval|uuid_generate|gen_random_uuid'
            SQL
          end

          pk = result.shift
          if result.last
            [pk, YugabyteDB::Name.new(*result)]
          else
            [pk, nil]
          end
        rescue
          nil
        end

        def remove_index(table_name, column_name = nil, **options) # :nodoc:
          table = Utils.extract_schema_qualified_name(table_name.to_s)

          if options.key?(:name)
            provided_index = Utils.extract_schema_qualified_name(options[:name].to_s)

            options[:name] = provided_index.identifier
            table = YugabyteDB::Name.new(provided_index.schema, table.identifier) unless table.schema.present?

            if provided_index.schema.present? && table.schema != provided_index.schema
              raise ArgumentError.new("Index schema '#{provided_index.schema}' does not match table schema '#{table.schema}'")
            end
          end

          return if options[:if_exists] && !index_exists?(table_name, column_name, **options)

          index_to_remove = YugabyteDB::Name.new(table.schema, index_name_for_remove(table.to_s, column_name, options))

          execute "DROP INDEX #{index_algorithm(options[:algorithm])} #{quote_table_name(index_to_remove)}"
        end

        def update_table_definition(table_name, base) # :nodoc:
          YugabyteDB::Table.new(table_name, base)
        end

        def create_schema_dumper(options) # :nodoc:
          YugabyteDB::SchemaDumper.create(self, options)
        end
      end
    end
  end
end
