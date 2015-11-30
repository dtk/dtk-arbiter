require File.expand_path('lib/workers/action', File.dirname(__FILE__))


agent = Arbiter::Action::Worker.new({ request_id: 1 }, nil)
agent.process