# frozen_string_literal: true

require "arel/visitors/postgresql"

module Arel # :nodoc: all
  module Visitors
    class YugabyteDB < PostgreSQL
    end
  end
end
