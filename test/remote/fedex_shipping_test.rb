require 'test_helper'

class FedShippingTest < Test::Unit::TestCase

  def setup
    @packages  = TestFixtures.packages
    @locations = TestFixtures.locations
    FedEx.include_ship_support!
    @carrier   = FedEx.new(fixtures(:fedex).merge(:test => true))
  end
    
  def test_valid_credentials
  #  assert @carrier.valid_credentials?
  end

  def test_shipment
      shipper = Shipper.new(
                            :shipper_number => fixtures(:fedex)[:account],
                            :name => "AllMed",
                            :country => 'US',
                            :city => 'Jefferson City',
                            :state => 'MO',
                            :address1 => '4715 Scruggs Station Rd',
                            :address2 => '',
                            :address_type=>'commercial',
                            :zip => '65109')
      
      shipment = Shipment.new(
                              :shipper => shipper,
                              :payer => shipper,
                              :destination => @locations[:new_york_with_name],
                              :packages => [ @packages[:all_imperial] ],
                              :printer => Printer.new({   :label_format=>'COMMON2D',
                                                          :label_image_type=>'EPL2',
                                                          :paper_stock_type=>'STOCK_4X8'
                                                      }),
                              :number => '3233',
                              :service => 'FEDEX_2_DAY' 
                              )

      shipment.packages.first.shipper_type_id = FedEx::PackageTypes['fedex_envelope']

      shipment.shipper.contact = shipment.destination.contact = Contact.new({ 
                                         :name=>'Jill Smith',
                                         :title=>'WH Supervisor',
                                         :company_name=>'AllMed',
                                         :phone_number=>'888-633-6908',
                                         :email_address=>'shipping@allmed.net'
                                     })

      @carrier.ship( shipment, :test=>true )
      

      assert shipment.labels.first.tracking

      File.open('/tmp/label.bin','w') do | lp |
          lp.write shipment.labels.first.image
      end

      File.open('/tmp/req.xml','w') do | db |
          xml = REXML::Document.new( shipment.log.first )
          xml.write( db, 2 )
      end
      File.open('/tmp/resp.xml','w') do | db |
          xml = REXML::Document.new( shipment.log.last )
          xml.write( db, 2 )
      end

  end
end
