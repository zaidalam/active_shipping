module ActiveMerchant #:nodoc:
    module Shipping #:nodoc:
        class Printer

            attr_accessor :label_format, :label_image_type, :paper_stock_type, :width, :height
            def initialize(attrs = {})
                attrs.each do |key, value|
                    self.send("#{key}=", value) if self.respond_to?("#{key}=")
                end
            end
            
        end
    end
end
