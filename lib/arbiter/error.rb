module DTK::Arbiter
  class ErrorFormatter
    class << self

      def action_not_defined(action_name, worker_clazz)
        format_error_message("Action '%s' for worker '%s' not defined, aborting action.", action_name, worker_clazz)
      end

    private

      def format_error_message(error_msg, *params)
        sprintf(error_msg, *params)
      end

    end
  end

  # list of application throwable errors
  class ArbiterError   < StandardError
    attr_reader :error_type
  end

  class MissingParams         < ArbiterError; def initialize(content); super(content); @error_type = :missing_params; end end
  class InvalidContent        < ArbiterError; def initialize(content); super(content); @error_type = :invalid_content; end end
  class ActionAbort           < ArbiterError; def initialize(content); super(content); @error_type = :abort_action; end end
  class YumLock               < ArbiterError; def initialize(content); super(content); @error_type = :yum_lock; end end
  class NotFound              < ArbiterError; def initialize(content); super(content); @error_type = :not_found; end end
  class NotSupported          < ArbiterError; def initialize(content); super(content); @error_type = :not_supported; end end
  class MissingDynAttributes  < ArbiterError; def initialize(content); super(content); @error_type = :user_error; end end
  class ArbiterExit           < ArbiterError; def initialize(content); super(content); @error_type = :arbiter_exit; end end

end
