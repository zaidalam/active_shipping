module ActiveMerchant
    module Shipping
        class Label
            attr_reader :tracking, :data, :format
            
            def initialize(attributes = {})
                @tracking = attributes[:tracking]
                @data = attributes[:data]
                @format = attributes[:format]
            end
        end
    end
end
