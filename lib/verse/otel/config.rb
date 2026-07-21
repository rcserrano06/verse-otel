# frozen_string_literal: true

require "verse/schema"

module Verse
  module Otel
    Config = Struct.new(
      :enabled,
      :service_name_prefix,
      :instrumentations,
      :db_statement,
      :untraced_hosts,
      keyword_init: true
    )

    class Config
      DB_STATEMENT_MODES = %i[include obfuscate omit].freeze

      Schema = Verse::Schema.define do
        field(:enabled, [TrueClass, FalseClass]).default(true)
        field(:service_name_prefix, String).default("")
        field(:instrumentations, Array, of: Symbol).default([])
        field(:db_statement, Symbol)
          .default(:obfuscate)
          .rule("must be one of #{DB_STATEMENT_MODES.join(", ")}") { |v| DB_STATEMENT_MODES.include?(v) }
        field(:untraced_hosts, Array, of: String).default([])

        transform { |schema| Config.new(**schema) }
      end
    end
  end
end
