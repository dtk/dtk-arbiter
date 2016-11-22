### Welcome to Dtk Arbiter


###### Description

Dtk Arbiter is ruby process which uses EventMachine for continus running. It can be run either in foreground or using the provided init scripts.

Dtk Arbiter is small process meant to be distributed on remote nodes to provide communication via STOMP. It aggregates and communicates with master nodes and it is easily extendable. It commes with parallel worker execution and strong SSH based message encryption. It has been developed to replace Mcollective functionality with its much simplfied and efficient design.

##### Requirements

* Ruby 1.9.3+
* Unix

###### Ruby

Make sure that Bundler gem is installed.

    gem install bundler

### Setup

##### Arbiter

After cloning project from github make sure you run following command

    bundle install

##### Environment

Arbiter uses dotenv gem to setup environment in development mode. File named `.env` has not been commited due to obvious security implications. Following are environment variables needed to start Dtk Arbiter.

    STOMP_HOST=
    STOMP_PORT=
    STOMP_USERNAME=
    STOMP_PASSWORD=
    INBOX_TOPIC=/topic/arbiter.dtk
    OUTBOX_QUEUE=/queue/arbiter.reply

This would be template for `.env` file needed in Dtk Arbiter folder.

If available, it can also read the MCollective server configuration file (`/etc/mcollective/server.cfg`).

### Run

From dtk-arbiter folder run command:

    ruby start.rb [--development]

### Calls from dtk client

From `dtk:/developer>` you can run:

    run-agent dock-test system_agent "{'module_name':'r8::stdlib','action_name':'get_ps','top_task_id':100000001,'task_id':100000002 }"
    run-agent dock-test action_agent "{'module_name':'r8::stdlib','action_name':'create','top_task_id':100000001,'task_id':100000002,'execution_list':[{'type':'syscall','command':'sleep 10; echo foo;','timeout':0,'stdout_redirect':true}]}"


