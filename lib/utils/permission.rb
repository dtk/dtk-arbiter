module Arbiter
  module Utils
    class Permission

      PERMISSION_CHECKER = /^[01]?[0-7]{3}$/

      def self.check(permission_value)
        !permission_value.to_s.match(PERMISSION_CHECKER).nil?
      end

    end
  end
end