require 'money'
require 'base64'

module ActiveMerchant
    module Shipping
        module FedExShippingSupport
            
            def ship( shipment, options={} )
                
                req = build_shipment_request(shipment)
                shipment.log(req)
                response = commit(save_request(req), (options[:test] || false)).gsub(/<(\/)?.*?\:(.*?)>/, '<\1\2>')
                shipment.log(response)
                parse_shipment_response(response, shipment)
                shipment   
            end
            
            def cancel(shipment, options={})

              req = build_delete_shipment_package_request(shipment)
              shipment.log(req)
              response = commit(save_request(req), (options[:test] || false)).gsub(/<(\/)?.*?\:(.*?)>/, '<\1\2>')
              shipment.log(response)
              parse_delete_shipment_package_response(response, shipment)
              shipment
            end

            def parse_shipment_response(response, shipment)

                xml = REXML::Document.new(response)
                if response_success?(xml)
                    root = xml.elements.first
                    root.elements['//Image'].each_with_index do | label,index |
                        shipment.labels << Label.new(
                                                     :tracking => xml.elements['//TrackingNumber'][index].to_s.strip,
                                                     :data    => Base64.decode64( label.to_s )
                                                     )
                    end
                    shipment.tracking = root.elements['//TrackingNumber'][0].to_s
                else
                    shipment.errors.push( response_message(xml) )
                end
            end
            
            def parse_delete_shipment_package_response(response, shipment)
              xml = REXML::Document.new(response)
              if response_success?(xml)
                shipment.tracking = nil
              else
                shipment.errors.push( response_message(xml) )
              end
            end

            def build_delete_shipment_package_request(shipment_package)
              xml_request = XmlNode.new('DeleteShipmentRequest', 'xmlns' => 'http://fedex.com/ws/ship/v10') do |root_node|
                  root_node << build_request_header
                  root_node << XmlNode.new('Version') do |version_node|
                      version_node << XmlNode.new('ServiceId', 'ship')
                      version_node << XmlNode.new('Major', '10')
                      version_node << XmlNode.new('Intermediate', '0')
                      version_node << XmlNode.new('Minor', '0')
                  end
                  root_node << XmlNode.new('TrackingId') do |tracking_id|
                    tracking_id << XmlNode.new('TrackingIdType', 'EXPRESS') #Should make it dynamic
                    tracking_id << XmlNode.new('TrackingNumber', shipment_package.tracking)
                  end
                  if shipment_package.is_a? Shipment #Check if shipment_package is instance of shipment
                    root_node << XmlNode.new('DeletionControl', 'DELETE_ALL_PACKAGES')
                  else
                    root_node << XmlNode.new('DeletionControl', 'DELETE_ONE_PACKAGE')
                  end
              end
              xml_request.to_s
            end

            def build_shipment_request(shipment)
                xml_request = XmlNode.new('ProcessShipmentRequest',
                                          'xmlns' => 'http://fedex.com/ws/ship/v7') do |root_node|
                    root_node << build_request_header
                    root_node << XmlNode.new('Version') do |version_node|
                        version_node << XmlNode.new('ServiceId', 'ship')
                        version_node << XmlNode.new('Major', '7')
                        version_node << XmlNode.new('Intermediate', '0')
                        version_node << XmlNode.new('Minor', '0')
                    end
                    
                    root_node << XmlNode.new('RequestedShipment') do |rs|
                        rs << XmlNode.new('ShipTimestamp', shipment.shipped_at )
                        rs << XmlNode.new('DropoffType', shipment.dropoff_type || 'REGULAR_PICKUP' )
                        rs << XmlNode.new('ServiceType', shipment.service)
                        rs << XmlNode.new('PackagingType', shipment.packages.first.shipper_type_id )
                        rs << XmlNode.new('TotalWeight') do |t|
                            if shipment.packages.first.using_metric? 
                                t << XmlNode.new('Units', 'KG')
                                t << XmlNode.new('Value', shipment.packages.reduce(0){|sum,p| sum+= p.kgs } )
                            else
                                t << XmlNode.new('Units', 'LB')
                                t << XmlNode.new('Value', shipment.packages.reduce(0){|sum,p| sum+= p.lbs } )
                            end
                        end
                        if shipment.packages.first.insured_value
                            rs << XmlNode.new('TotalInsuredValue') do |ins|
                                ins << XmlNode.new('Currency', shipment.packages.first.currency)
                                ins << XmlNode.new('Amount', shipment.packages.first.insured_value )
                            end
                        end
                        rs << build_party_node('Shipper', shipment.shipper)
                        rs << build_party_node('Recipient', shipment.destination )
                        rs << XmlNode.new('ShippingChargesPayment') do |payment|
                            payment << XmlNode.new('PaymentType', shipment.payer.payment_type || 'SENDER')
                            payment << XmlNode.new('Payor') do |payor|
                                payor << XmlNode.new('AccountNumber', shipment.payer.shipper_number)
                                payor << XmlNode.new('CountryCode', shipment.payer.country.code(:alpha2))
                            end
                        end

                        if shipment.is_a?( ReturnShipment )
                            rs << XmlNode.new('SpecialServicesRequested') do |s|
                                s << XmlNode.new('SpecialServiceTypes', 'RETURN_SHIPMENT')
                                s << XmlNode.new('ReturnShipmentDetail') do |d|
                                    d << XmlNode.new('ReturnType', shipment.return_type)
                                    d << XmlNode.new('Rma') do |rma|
                                        rma << XmlNode.new('Number', shipment.rma_number)
                                    end
                                end
                            end
                        end

                        rs << XmlNode.new('LabelSpecification') do |spec|
                            spec << XmlNode.new('LabelFormatType', shipment.printer.label_format     || 'COMMON2D')
                            spec << XmlNode.new('ImageType',       shipment.printer.label_image_type || 'PNG' )
                            spec << XmlNode.new('LabelStockType',  shipment.printer.paper_stock_type || 'PAPER_4X6')
                        end
                        rs << XmlNode.new('RateRequestTypes', shipment.rate_request_type || 'ACCOUNT')
                        rs << XmlNode.new('PackageCount', shipment.packages.count )
                        rs << XmlNode.new('PackageDetail', 'PACKAGE_SUMMARY')
                        (1..shipment.packages.count).each do |package_index|
                            rs << XmlNode.new('RequestedPackageLineItems') do |p|
                                p << XmlNode.new('SequenceNumber', package_index)
                                p << XmlNode.new('Weight') do |w|
                                    if shipment.packages.first.using_metric? 
                                        w << XmlNode.new('Units', 'KG')
                                        w << XmlNode.new('Value', shipment.packages.reduce(0){|sum,p| sum+= p.kgs } )
                                    else
                                        w << XmlNode.new('Units', 'LB')
                                        w << XmlNode.new('Value', shipment.packages.reduce(0){|sum,p| sum+= p.lbs } )
                                    end
                                end
                                # JDW: Assigning all the weight to the first item to get around a FedEx bug. Once FeEx fixes the bug
                                # it should be possible (and correct) to remove the Weight element entirely.
 
                            end
                        end
                    end
                end

                xml_request.to_s
            end

            def build_party_node(name, party)
                XmlNode.new(name) do |xml_node|
                    if party.shipper_number
                        xml_node << XmlNode.new('AccountNumber', party.shipper_number )
                    end

                    if party.contact
                        xml_node << XmlNode.new('Contact') do |c|
                            c << XmlNode.new('PersonName', party.contact.name)
                            c << XmlNode.new('Title', party.contact.title)
                            c << XmlNode.new('CompanyName', party.contact.company_name)
                            c << XmlNode.new('PhoneNumber', party.contact.phone_number)
                            c << XmlNode.new('FaxNumber', party.contact.fax_number)
                            c << XmlNode.new('EMailAddress', party.contact.email_address)
                        end
                    end

                   # if 'Recipient' == name
                        xml_node << build_party_location_node('Address', party )
                  #  end
                end
            end

            def build_party_location_node(name, location)
                XmlNode.new(name) do |a|
                    if location.address1
                        a << XmlNode.new('StreetLines', location.address1)
                    end

                    if location.address2
                        a << XmlNode.new('StreetLines', location.address2)
                    end

                    a << XmlNode.new('City', location.city)
                    a << XmlNode.new('StateOrProvinceCode', location.state)
                    a << XmlNode.new('PostalCode', location.zip)
                    a << XmlNode.new('CountryCode', location.country.code(:alpha2))
                end
            end




        end
    end
end
