module DTK
  module Arbiter
    module Utils
      Dir["utils/*.rb"].each do |file_path|
        require File.expand_path("../../#{file_path}", __FILE__)
      end
    end
  end
end
