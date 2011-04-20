module ActiveMerchant
    module Shipping
        class ReferenceNumber
            attr_accessor :code, :value
            def initialize( code, value )
                @code=code
                @value=value
            end
        end
    end
end
