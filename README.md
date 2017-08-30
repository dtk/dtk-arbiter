### Dtk Arbiter


##### Description

Dtk Arbiter is ruby process which uses EventMachine for continus running. It can be run either in foreground or using the provided init scripts.

Dtk Arbiter is small process meant to be distributed on remote nodes to provide communication via STOMP. It aggregates and communicates with master nodes and it is easily extendable. It commes with parallel worker execution and strong SSH based message encryption. It has been developed to replace Mcollective functionality with its much simplfied and efficient design.

##### Requirements

* Ruby 2.0.0+
* Unix

###### Ruby

Make sure that Bundler gem is installed.

    gem install bundler

### Setup

##### Arbiter

After cloning project from github make sure you run following command

    bundle install

##### Configuration
Arbiter will look for a configuration located at `/etc/dtk/arbiter.cfg`. Example of the config file: [arbiter.cfg.example](etc/arbiter.cfg.example)

####Development

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

#### Docker
Arbiter can also be started as a docker container: 

    docker run --name dtk-arbiter \
               -v /usr/share/dtk:/host_volume \ 
               -v /var/run/docker.sock:/var/run/docker.sock \
               -e HOST_VOLUME=/usr/share/dtk/ \
               -td getdtk/dtk-arbiter

Full list of environment variables that can be passed to the arbiter container:

	STOMP_USERNAME
	STOMP_PASSWORD
	STOMP_PORT
    GIT_PORT
	GIT_USERNAME
	PBUILDERID
	PRIVATE_KEY_NAME
	LOG_LEVEL
	DEVELOPMENT_MODE




