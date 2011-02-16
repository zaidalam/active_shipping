module ActiveMerchant
  module Shipping
    class Contact
      attr_accessor :name
      attr_accessor :title
      attr_accessor :company_name
      attr_accessor :phone_number
      attr_accessor :fax_number
      attr_accessor :email_address

      def initialize(attrs = {})
        attrs.each do |key, value|
          self.send("#{key}=", value) if self.respond_to?("#{key}=")
        end
      end
    end
  end
end
