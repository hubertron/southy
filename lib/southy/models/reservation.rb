module Southy
  class Reservation < ActiveRecord::Base
    validates :confirmation_number, presence: true, uniqueness: { case_insensitive: true }
    validates :origin_code, presence: true
    validates :destination_code, presence: true

    has_one  :source,     dependent: :destroy
    has_many :bounds,     dependent: :destroy
    has_many :passengers, dependent: :destroy

    scope    :upcoming, -> { joins(:bounds).where("bounds.departure_time >= '#{Date.today}'").distinct }

    def conf
      confirmation_number
    end

    def origin_airport
      Airport.lookup origin_code
    end

    def destination_airport
      Airport.lookup destination_code
    end

    def ==(other)
      conf == other.conf &&
        origin_code == other.origin_code &&
        destination_code == other.destination_code
        bounds == other.bounds &&
        passengers == other.passengers
    end

    def ident
      "#{conf} (#{passengers.first.name})"
    end

    def self.matches?(reservation)
      existing = Reservation.where confirmation_number: reservation.conf
      existing && existing.first == reservation
    end

    def self.from_json(json)
      res = Reservation.new
      res.source = Source.new
      res.source.json = json

      throw SouthyException.new("No inbound or outbound flights") unless json.bounds
      throw SouthyException.new("No passengers") unless json.passengers

      res.confirmation_number = json.confirmationNumber
      res.origin_code         = json.originAirport.code
      res.destination_code    = json.destinationAirport.code

      Airport.validate res.origin_code
      Airport.validate res.destination_code

      res.bounds = json.bounds.map do |boundJson|
        bound                = Bound.new
        bound.flights        = boundJson.flights.map(&:number)
        bound.departure_code = boundJson.departureAirport.code
        bound.arrival_code   = boundJson.arrivalAirport.code
        bound.departure_time = bound.departure_airport.local_time boundJson.departureDate, boundJson.departureTime
        bound.arrival_time   = bound.arrival_airport.local_time   boundJson.departureDate, boundJson.arrivalTime
        Airport.validate bound.departure_code
        Airport.validate bound.arrival_code

        bound.stops = boundJson.stops.map do |stopJson|
          stop                = Stop.new
          stop.code           = stopJson.airport.code
          stop.arrival_time   = stop.airport.local_time boundJson.departureDate, stopJson.arrivateTime
          stop.departure_time = stop.airport.local_time boundJson.departureDate, stopJson.departureTime
          Airport.validate stop.code
          stop
        end

        bound
      end

      res.passengers = json.passengers.map do |passengerJson|
        passenger      = Passenger.new
        passenger.name = passengerJson.name
        passenger
      end

      res
    end

    def self.list(reservations, options = {})
      return "No upcoming reservations" if reservations.empty?

      max_name   = reservations.map(&:passengers).flatten.map(&:name).map(&:length).max
      max_depart = reservations.map(&:bounds).flatten.map(&:departure_airport).map(&:name).map(&:length).max + 6
      max_arrive = reservations.map(&:bounds).flatten.map(&:arrival_airport).map(&:name).map(&:length).max + 6

      out = ""
      reservations.each do |r|
        r.bounds.each do |b|
          r.passengers.each_with_index do |p, i|
            leader = i == 0 ? sprintf("#{r.conf} - SW%-4s", b.flights.first) : "               "
            name   = sprintf "%-#{max_name}s", p.name
            time   = b.departure_time.strftime "%Y-%m-%d %l:%M%p"
            depart = sprintf "%#{max_depart}s", "#{b.departure_airport.name} (#{b.departure_airport.code})"
            arrive = sprintf "%#{max_arrive}s", "#{b.arrival_airport.name} (#{b.arrival_airport.code})"

            out += "#{leader}: #{name}  #{time}  #{depart} -> #{arrive}\n"
          end
        end
      end

      out
    end
  end
end
