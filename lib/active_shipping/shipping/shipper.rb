module ActiveMerchant #:nodoc:
    module Shipping #:nodoc:
        class Shipper < Location

            def initialize(options = {})
                super( options )
            end
            
            def location=(loc)
                @country = loc.country
                @postal_code = loc.postal_code
                @province = loc.province
                @city = loc.city
                @address1 = loc.address1
                @address2 = loc.address2
                @address3 = loc.address3
                @phone = loc.phone
                @fax = loc.fax
                @address_type = loc.address_type
                @name = loc.name
                @attention = loc.attention
            end
        end
    end    
end


        
