### Welcome to DTK Arbiter

##### Requirements

* System
* Ruby 1.9.3+

###### System

DTK Arbiter is ruby process which uses EventMachine for continus running. It can be run either in foreground or using the provided init scripts.

###### Ruby

Make sure that Bundler gem is installed.

    gem install bundler

### Setup

##### Arbiter

After cloning project from github make sure you run following command

    bundle install

##### Environment

Arbiter uses dotenv gem to setup environment in development mode. File named `.env` has not been commited due to obvious security implications. Following are environment variables needed to start DTK Arbiter.

    STOMP_HOST=
    STOMP_PORT=
    STOMP_USERNAME=
    STOMP_PASSWORD=
    INBOX_TOPIC=mcollective.dtk.reply
    OUTBOX_TOPIC=mcollective.dtk

This would be template for `.env` file needed in DTK Arbiter folder.

If available, it can also read the MCollective server configuration file (`/etc/mcollective/server.cfg`).

### Run

From dtk-arbiter folder run command:

    ruby start.rb

### Calls from dtk client

From `dtk:/developer>` you can run:

    run-agent dock-test system_agent "{'module_name':'r8::stdlib','action_name':'get_ps','top_task_id':100000001,'task_id':100000002 }"
    run-agent dock-test action_agent "{'module_name':'r8::stdlib','action_name':'create','top_task_id':100000001,'task_id':100000002,'execution_list':[{'type':'syscall','command':'sleep 10; echo jao;','timeout':0,'stdout_redirect':true}]}"


