require File.expand_path('lib/workers/action_agent', File.dirname(__FILE__))


agent = Arbiter::Action::AgentWorker.new({ request_id: 1 }, nil)
agent.process