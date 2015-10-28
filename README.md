### Welcome to DTK Arbiter

##### Requirements

* System
* Ruby 1.9.3+

###### System

DTK Arbiter is ruby process which uses EventMachine for continus running, transforming it into system service would be recommended.

###### Ruby

Make sure that Bundler gem is installed.

  gem install bundler

### Setup

##### Arbiter

After cloning project from github make sure you run following command

    bundle install

##### Environment

Arbiter uses dotenv gem to setup environment. File named `.env` has not been commited due to obvious security implications. Following are environment variables needed to start DTK Arbiter.

  STOMP_HOST=
  STOMP_PORT=
  STOMP_USERNAME=
  STOMP_PASSWORD=
  INBOX_TOPIC=mcollective.dtk.reply
  OUTBOX_TOPIC=mcollective.dtk

This would be template for `.env` file needed in DTK Arbiter folder.

### Run

From dtk-arbiter folder run command:

  ruby start.rb


