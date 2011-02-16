module ActiveMerchant
    module Shipping
        class Label
            attr_reader :tracking, :image, :format
            
            def initialize(attributes = {})
                @tracking = attributes[:tracking]
                @image = attributes[:image]
                @format = attributes[:format]
            end
        end
    end
end
