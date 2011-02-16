## this is based off 

require 'money'
require 'base64'

module ActiveMerchant
    module Shipping

        module UPSShippingSupport

            def UPSShippingSupport.included( cls )
                cls::RESOURCES[:shipment_confirm] = 'ups.app/xml/ShipConfirm'
                cls::RESOURCES[:shipment_accept ] = 'ups.app/xml/ShipAccept'
            end

            def ship( shipment, options )
                request = build_shipment_confirm_request(shipment)
                
                shipment.log(request)
                
                response = commit(:shipment_confirm, save_request(build_access_request + request), (options[:test] || false))
                shipment.log(response)
                
                parse_shipment_confirm(shipment, response)
                
                if shipment.allowed_price_range.blank? || shipment.allowed_price_range.include( shipment.price )
                    
                    request = build_shipment_accept_request(shipment)
                    shipment.log(request)
                    response = commit(:shipment_accept, save_request(build_access_request + request), (options[:test] || false))
                    shipment.log(response)
                    parse_shipment_accept(shipment, response)
                end
                shipment
            end

            def cancel_shipment(shipment, options = {})
                request = build_void_shipment_request(shipment)
                shipment.log(request)
                response = commit(:void_shipment, save_request(build_access_request + request), (options[:test] || false))
                shipment.log(response)
                parse_void_shipment(shipment, response)
                shipment
            end  

            protected 
            
            def add_location(xml, name, object)
                xml.tag!(name) do
                    node_name = (name == 'Shipper' ? 'Name' : 'CompanyName')
                    xml.tag!(node_name, object.name)
                    if node_name == 'CompanyName' && !object.attention.blank?
                        xml.AttentionName object.attention
                    end
                    unless object.phone.blank?
                        xml.PhoneNumber object.phone.gsub(/[^\d]/, '')
                    end
                    unless object.fax.blank?
                        xml.FaxNumber object.phone.gsub(/[^\d]/, '')
                    end
                    if name == 'Shipper'
                        xml.ShipperNumber object.shipper_number
                    elsif name == 'ShipTo' && object.respond_to?(:shipper_number) && !object.shipper_number.blank?
                        xml.ShipperAssignedIdentificationNumber object.shipper_number
                    end
                    xml.Address do
                        values = [
                                  [object.address1, :AddressLine1],
                                  [object.address2, :AddressLine2],
                                  [object.address3, :AddressLine3],
                                  [object.city, :City],
                                  [object.province, :StateProvinceCode],
                                  [object.postal_code, :PostalCode],
                                  [object.country_code(:alpha2), :CountryCode],
                                  [!object.commercial?, :ResidentialAddressIndicator]
                                 ]
                        values.select {|v, n| v && v != '' }.each do |v, n|
                            xml.tag!(n, v)
                        end
                    end
                end
            end

            def add_reference(xml, shipment)
                if shipment.number
                    xml.TransactionReference do
                        xml.CustomerContext shipment.number
                    end
                end
            end

            def build_shipment_confirm_request(shipment)
                xml = Builder::XmlMarkup.new
                xml.instruct!
                xml.ShipmentConfirmRequest do
                    xml.Request do
                        xml.RequestAction 'ShipConfirm'
                        xml.RequestOption 'validate'
                        add_reference(xml, shipment)
                    end
                    xml.LabelSpecification do
                        xml.LabelPrintMethod { xml.Code shipment.printer.label_format }
                        if ( 'GIF' == shipment.printer.label_format )
                            xml.LabelImageFormat { xml.Code shipment.printer.label_format }
                        else
                            xml.LabelStockSize do 
                                xml.Height shipment.printer.height || 4
                                xml.Width  shipment.printer.width  || 8
                            end
                        end
                    end
                    xml.Shipment do
                    add_location(xml, 'Shipper',  shipment.shipper)
                    add_location(xml, 'ShipTo',   shipment.destination)
                        add_location(xml, 'ShipFrom', shipment.shipper )
                        xml.PaymentInformation do
                            xml.Prepaid do
                                xml.BillShipper do
                                    xml.AccountNumber shipment.payer.shipper_number
                                end
                            end
                        end
                        xml.Service { xml.Code shipment.service }
                        if shipment.value
                            xml.InvoiceLineTotal do
                                xml.CurrencyCode shipment.value.currency
                                xml.MonetaryValue shipment.value.cents.to_f / 100
                            end
                        end
                        shipment.packages.each do |package|
                            add_package(xml, package, shipment.shipper )
                        end
                    end
                end
                xml.target!
            end

            def build_shipment_accept_request(shipment)
                xml = Builder::XmlMarkup.new
                xml.instruct!
                xml.ShipmentAcceptRequest do
                    xml.Request do
                        xml.RequestAction 'ShipAccept'
                        add_reference(xml, shipment)
                    end
                    xml.ShipmentDigest shipment[:digest]
                end
                xml.target!
            end

            def build_void_shipment_request(shipment)
                xml = Builder::XmlMarkup.new
                xml.instruct!
                xml.VoidShimentRequest do
                    xml.Request do
                        xml.RequestAction '1'
                    end
                    add_reference(xml, shipment)
                end
                xml.ShipmentIdentificationNumber shipment.tracking
                xml.target!
            end

            def parse_shipment_confirm(shipment, response)
                xml = REXML::Document.new(response)
                if response_success?(xml)
                    confirm_response = xml.elements['/ShipmentConfirmResponse']
                    shipment.price = parse_money(confirm_response.elements['ShipmentCharges/TotalCharges'])
                    shipment[:digest] = confirm_response.text('ShipmentDigest')
                else
                    shipment.errors = response_message(xml)
                end
                shipment
            end

            def parse_money(element)
                value = element.elements['MonetaryValue'].text
                currency = element.elements['CurrencyCode'].text
                Money.new((BigDecimal(value) * 100).to_i, currency)
            end

            def parse_shipment_accept(shipment, response)
                xml = REXML::Document.new(response)
                if response_success?(xml)
                    shipment_results = xml.elements['/ShipmentAcceptResponse/ShipmentResults']
                    shipment.price = parse_money(shipment_results.elements['ShipmentCharges/TotalCharges'])
                    shipment.tracking = shipment_results.elements['ShipmentIdentificationNumber'].text
                    shipment.labels = []
                    shipment_results.elements.each('PackageResults') do |package_results|
                        shipment.labels << Label.new(
                                                     :tracking => package_results.text('TrackingNumber'),
                                                     :image    => Base64.decode64( package_results.text('LabelImage/GraphicImage') ),
                                                     :format   => package_results.text('LabelImage/LabelImageFormat/Code')
                                                     )
                    end
                else
                    shipment.errors = response_message(xml)
                end
                shipment
            end

            def parse_void_shipment(shipment, response)
                xml = REXML::Document.new(response)
                if response_success?(xml)
                    shipment.tracking = nil
                else
                    shipment.errors = response_message(xml)
                end
                shipment
            end

            def add_package(xml, package, origin)
                raise package.class.to_s unless package.kind_of?(ActiveMerchant::Shipping::Package)
                imperial = ['US','LR','MM'].include?(origin.country_code(:alpha2))
                xml.Package do
                    xml.PackagingType { xml.Code '02' }
                    unless package.description.blank?
                        xml.Description package.description
                    end
                    axes = [:length, :width, :height]
                    values = axes.map do |axis|
                        if imperial
                            package.inches(axis)
                        else
                            package.cm(axis)
                        end
                    end
                    if values.all? {|v| v > 0 }
                        xml.Dimensions do
                            xml.UnitOfMeasurement do
                                xml.Code(imperial ? 'IN' : 'CM')
                            end
                            axes.each_with_index do |axis, i|
                                value = (values[i].to_f * 1000).round / 1000.0
                                xml.tag!(axis.to_s.capitalize, [values[i], 0.1].max.to_s)
                            end
                        end
                    end
                    xml.PackageWeight do
                        xml.UnitOfMeasurement do
                            xml.Code(imperial ? 'LBS' : 'KGS')
                        end
                        value = (imperial ? package.lbs : package.kgs)
                        value = (value.to_f * 1000).round / 1000.0 # 3 decimals
                        xml.Weight [value, 0.1].max.to_s
                    end
                    if package.insured_value
                        xml.PackageServiceOptions do
                            xml.InsuredValue do
                                xml.CurrencyCode package.insured_value.currency
                                xml.MonetaryValue package.insured_value.cents.to_f / 100
                            end
                        end
                    end
                    # not implemented: * Shipment/Package/LargePackageIndicator element
                    # * Shipment/Package/ReferenceNumber element
                    # * Shipment/Package/AdditionalHandling element
                end
            end

        end

    end
end
