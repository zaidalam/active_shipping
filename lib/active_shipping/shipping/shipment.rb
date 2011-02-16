module ActiveMerchant
    module Shipping
        class Shipment
            attr_accessor :number, :price, :tracking, :shipper, :payer, :printer,
                          :destination, :service, :labels, :packages, :errors,:value,
                          :shipped_at, :dropoff_type, :rate_request_type, :allowed_price_range

            def initialize(attributes = {})
                attributes.each do |key, value|
                    self.send("#{key}=", value) if self.respond_to?("#{key}=")
                end
                @shipped_at = attributes[:shipped_at] || Time.now
                @attributes = attributes
                @errors = []
                @labels = []
                @log = []
            end

            def [](name)
                @attributes.try(:[], name)
            end

            def []=(name, value)
                @attributes.try(:[]=, name, value)
            end

            def log(value = nil)
                if value
                    @log << value
                else
                    @log
                end
            end
        end
    end
end


