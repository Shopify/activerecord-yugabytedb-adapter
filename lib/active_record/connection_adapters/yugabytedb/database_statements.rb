# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module YugabyteDB
      module DatabaseStatements
        private
          IDLE_TRANSACTION_STATUSES = [YSQL::PQTRANS_IDLE, YSQL::PQTRANS_INTRANS, YSQL::PQTRANS_INERROR]
          private_constant :IDLE_TRANSACTION_STATUSES

          def cancel_any_running_query
            return if @raw_connection.nil? || IDLE_TRANSACTION_STATUSES.include?(@raw_connection.transaction_status)

            @raw_connection.cancel
            @raw_connection.block
          rescue YSQL::Error
          end
      end
    end
  end
end
