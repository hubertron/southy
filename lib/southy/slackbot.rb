require 'slack-ruby-client'
require 'set'

module Southy
  class Slackbot
    def initialize(config, travel_agent, service)
      @config = config
      @agent = travel_agent
      @service = service
      @restarts = []
      @channels = Set.new

      @conversions = {
        'Yasmine Molavi' => [ 'Yasaman', 'Molavi Vassei' ]
      }

      Slack.configure do |slack_cfg|
        slack_cfg.token = @config.slack_api_token
      end

    end

    def run
      @webclient = Slack::Web::Client.new
      auth = @webclient.auth_test
      if auth['ok']
        puts "Slackbot is active!"
        @config.log "Slackbot is active!"
        @config.log "Accepting channels: #{@config.slack_accept_channels}" if @config.slack_accept_channels.length > 0
        @config.log "Ignoring channels: #{@config.slack_reject_channels}" if @config.slack_reject_channels.length > 0
      else
        @config.log "Slackbot is doomed :-("
        return
      end

      client = Slack::RealTime::Client.new

      client.on :message do |data|
        next if data['user'] == 'U0HM6QX8Q' # this is Mr. Southy!
        next unless data['text']
        tokens = data['text'].split ' '
        channel = data['channel']
        next unless tokens.length > 0
        next unless tokens[0].downcase == 'southy'
        next if @config.slack_accept_channels.length > 0 and ! @config.slack_accept_channels.index(channel)
        next if @config.slack_reject_channels.index channel
        message = Southy::Message.new client, channel
        message.type
        @channels << channel
        ( help(data, [], message) and next ) unless tokens[1]
        method = tokens[1].downcase
        args = tokens[2..-1]
        method = "#{method}_all" if args == [ 'all' ]
        send method, data, args, message
      end

      client.start!
    rescue => e
      @config.log "An error ocurring inside the Slackbot", e
      @restarts << Time.new
      @restarts.shift while (@restarts.length > 3)
      if @restarts.length == 3 and ( Time.new - @restarts.first < 30 )
        @config.log "Too many errors.  Not restarting anymore."
        client.on :hello do
          @channels.each do |channel|
            client.message channel: channel, text: "Oh no... I have died!  Please make me live again @mike"
          end
          client.stop!
        end
        client.start!
      else
        run
      end
    end

    def method_missing(name, *args)
      @config.log "No method found for: #{name}"
      @config.log args[0]
    end

    def user_profile(data)
      id = data['user']
      res = @webclient.users_info user: id
      return {} unless res['ok']
      profile = res['user']['profile']
      first = profile['first_name']
      last = profile['last_name']
      converted = @conversions["#{first} #{last}"]
      if converted
        first = converted[0]
        last = converted[1]
      end
      { id: id, first_name: first, last_name: last, full_name: "#{first} #{last}", email: profile['email'] }
    end

    def help(data, args, message)
      message.reply "Hello, I am Southy.  I can do the following things:"
      message.reply <<EOM
```
southy help              Show this message
southy hello             Say hello to me!
southy whatsup           Show me ALL the flights upcoming
southy list              Show me what flights I have upcoming
southy history           Show me what flights I had in the past
southy add <conf>        Add this flight to Southy
southy remove <conf>     Remove this flight from Southy
southy reconfirm         Reconfirm your flights, if you have changed flight info

<conf> = Your flight confirmation number and optionally contact info, for example:
         southy add RB7L6K     <-- uses your name and email from Slack
         southy add RB7L6K Joey Shabadoo joey@snpp.com
```
EOM
    end

    def blowup(data, args, message)
      message.reply "Tick... tick... tick... BOOM!   Goodbye."
      EM.next_tick do
        raise "kablammo!"
      end
    end

    def hello(data, args, message)
      profile = user_profile data
      if profile[:first_name] and profile[:last_name] and profile[:email]
        message.reply "Hello #{profile[:first_name]}!  You are all set to use Southy."
        message.reply "I will use this information when looking up your flights:"
        message.reply <<EOM
```
name:  #{profile[:first_name]} #{profile[:last_name]}
email: #{profile[:email]}
```
EOM
      else
        message.reply "Hello.  You are not set up yet to use Southy.  You need to fill in your first name, last name and email in your Slack profile."
      end
    end

    def print_bounds(bounds, message)
      if !bounds || bounds.empty?
        message.reply "```No available flights.```"
        return
      end

      bounds.sort_by(&:departure_time).each_slice(10) do |slice|
        message.reply('```' + Reservation.list(slice, short: true) + '```')
      end
    end

    def list(data, args, message)
      profile = user_profile data
      message.reply "Upcoming Southwest flights for #{profile[:full_name]}:"
      message.type
      if args && args.length > 0
        bounds = Bound.upcoming.for_reservation args[0]
      else
        bounds = Bound.upcoming.for_person profile[:email], profile[:full_name]
      end
      print_bounds bounds, message
    end

    def list_all(data, args, message)
      message.reply "Upcoming Southwest flights:"
      message.type
      bounds = Bound.upcoming
      print_bounds bounds, message
    end

    def whatup(data, args, message)
      whatsup data, args, message
    end

    def whatsup(data, args, message)
      list_all data, args, message
      message.reply "```You can type 'southy help' to see more commands```"
    end

    def history(data, args, message)
      profile = user_profile data
      message.reply "Previous Southwest flights for #{profile[:full_name]}:"
      message.type
      bounds = Bound.past.for_person profile[:email], profile[:full_name]
      print_bounds bounds, message
    end

    def history_all(data, args, message)
      message.reply "Previous Southwest flights:"
      message.type
      bounds = Bound.past
      print_bounds bounds, message
    end

    def add(data, args, message)
      args.tap do |(conf, fname, lname, email)|
        return ( message.reply "You didn't enter a confirmation number!" ) unless conf

        if Bound.for_reservation(conf).length > 0
          message.reply "That reservation already exists. Try `southy reconfirm #{conf}`"
          return
        end

        profile = user_profile data
        unless fname and lname
          fname = profile[:first_name]
          lname = profile[:last_name]
        end
        unless email
          email = profile[:email]
        end
        if email && match = email.match(/^<mailto:(.*)\|/)
          email = match.captures[0]
        end

        reservation = confirm_reservation conf, fname, lname, email, message
        print_bounds reservation&.bounds, message
      end
    end

    def remove(data, args, message)
      args.tap do |(conf)|
        return ( message.reply "You didn't enter a confirmation number!" ) unless conf
        deleted = Reservation.where(confirmation_number: conf).destroy_all
        l = deleted.length
        message.reply "Removed #{deleted.length} reservation(s) - #{deleted.map(&:conf).join(', ')}"
      end
    end

    def reconfirm(data, args, message)
      profile = user_profile data
      reservations = Reservation.upcoming.for_person profile[:email], profile[:full_name]
      if reservations.empty?
        message.reply "No flights available for #{profile[:full_name]}"
        return
      end

      reservations = confirm_reservations reservations, message
      print_bounds reservations.map(&:bounds).flatten, message
    end

    def reconfirm_all(data, args, message)
      reservations = Reservation.upcoming
      if reservations.empty?
        message.reply "No flights available"
        return
      end

      reservations = confirm_reservations reservations, message
      print_bounds reservations.map(&:bounds).flatten, message
    end

    private

    def confirm_reservation(conf, first, last, email, message)
      message.reply "Confirming #{conf} for *#{first} #{last}*..."
      message.type
      reservation, is_new = @agent.confirm conf, first, last, email
      reservation
    rescue SouthyException => e
      message.reply "Could not confirm reservation #{conf} - #{e.message}"
      nil
    end

    def confirm_reservations(reservations, message)
      reservations.sort_by { |r| r.bounds.first.departure_time }.map do |r|
        confirm_reservation r.conf, r.first_name, r.last_name, r.email, message
      end
    end
  end
end
