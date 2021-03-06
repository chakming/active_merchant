require 'active_support/version' # for ActiveSupport2.3
require 'digest/md5'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    module Integrations #:nodoc:
      module Migs
        class Helper < ActiveMerchant::Billing::Integrations::Helper
          include RequiresParameters

          ELECTRON = /^(424519|42496[23]|450875|48440[6-8]|4844[1-5][1-5]|4917[3-5][0-9]|491880)\d{10}(\d{3})?$/

          # WARNING
          #
          # From reading most of the tests for various integrations,
          # including the more popular ones (Authorize.net), it seems
          # that the amount field is provided using dollars, not cents
          # like the Gateway classes. The currency for transactions is
          # dictated by the merchant account. Thus, the user will need
          # to determine the correct amount. It seems that cents are
          # used for USD and INR at the very least.

          # The MiGS merchant id should be passed as the account parameter.
          #
          # Options must include:
          #
          # - :locale
          # - :access_code => Migs access code
          # - :secret => Migs secure secret
          # - :amount => price in cents
          #
          # Also, the method add_secure_hash should be called at the very end
          # of the block passed to payment_service_for.
          def initialize(order, account, options = {})
            requires!(options, :amount, :locale, :secret, :access_code)

            # The following elements need to be removed from params to not
            # trigger an error, but can't be added to the object yet since
            # the @fields Hash has not been set up yet via super()
            locale = options.delete(:locale)
            access_code = options.delete(:access_code)
            # For generating the secure hash
            secret = options.delete(:secret)

            super

            add_field('vpc_gateway', 'ssl')
            add_field('vpc_Command', 'pay')
            add_field('vpc_Version', '1')
            add_field('vpc_VirtualPaymentClientURL', 'https://migs.mastercard.com.au/vpcpay')

            self.locale = locale
            self.access_code = access_code
            @secret = secret
          end

          # A custom handler for credit cards to extract the card type
          # since Migs wants that passed with the data
          def credit_card(params = {})
            brand = params[:brand].to_sym
            params.delete(:brand)

            exp_month = sprintf("%.2i", params[:expiry_month])
            exp_year = sprintf("%.4i", params[:expiry_year])
            params.delete(:expiry_month)
            params.delete(:expiry_year)

            method_missing(:credit_card, params)

            # The expiration data needs to be combined together
            exp = "#{exp_year[-2..-1]}#{exp_month}"
            add_field(mappings[:credit_card][:expiry_month], exp)

            # Map the card type to what Migs is expecting
            if params[:number] =~ ELECTRON
              brand_name = 'VisaDebit'
            else
              brand_name = {
                :visa             => 'Visa',
                :master           => 'Mastercard',
                :american_express => 'Amex',
                :diners_club      => 'Dinersclub',
                :jcb              => 'JCB',
                :solo             => 'Solo'
              }[brand]
            end

            add_field(mappings[:credit_card][:brand], brand_name)
          end

          # Make sure the order id and attempt number are combined into
          # the appropriate fields in the form. The transaction reference
          # is constructed as:
          #
          # order-attempt_number
          #
          # The order info is constructed as:
          #
          # order-attempt_number/description

          def order=(value)
            # Both of these fields include the order id
            {'vpc_MerchTxnRef' => 40, 'vpc_OrderInfo' => 34}.each do |field, max_length|
              existing_value = @fields[field] || ""

              # Inserts the description as (/description) into any existing variation of "order-attempt/description"
              new_value = existing_value.gsub(/^(\d+)?(-\d+)?(\/.*)?$/, "#{value}\\2\\3")

              add_field(field, new_value[0...max_length])
            end
          end

          def attempt_number(value)
            # Both of these fields include the atempt_number
            {'vpc_MerchTxnRef' => 40, 'vpc_OrderInfo' => 34}.each do |field, max_length|
              existing_value = @fields[field] || ""

              # Inserts the attempt number as (-\d) into any existing variation of "order-attempt/description"
              new_value = existing_value.gsub(/^(\d+)?(-\d+)?(\/.*)?$/, "\\1-#{value}\\3")

              add_field(field, new_value[0...max_length])
            end
          end

          def description(value)
            field = 'vpc_OrderInfo'
            max_length = 34
            existing_value = @fields[field] || ""

            # Inserts the description as (/description) into any existing variation of "order-attempt/description"
            value = existing_value.gsub(/^(\d+)?(-\d+)?(\/.*)?$/, "\\1\\2/#{value}")

            add_field(field, value[0...max_length])
          end

          # This must be called at the end after all other fields have been added
          def add_secure_hash
            sorted_values = @fields.sort_by(&:to_s).map(&:last)
            input = @secret + sorted_values.join
            hash = Digest::MD5.hexdigest(input).upcase

            add_field('vpc_SecureHash', hash)
          end

          mapping :account, 'vpc_Merchant'
          mapping :access_code, 'vpc_AccessCode'
          mapping :locale, 'vpc_Locale'
          mapping :return_url, 'vpc_ReturnURL'
          mapping :amount, 'vpc_Amount'

          mapping :billing_address,  :city     => 'vpc_AVS_City',
                                     :address1 => 'vpc_AVS_Street_01',
                                     :state    => 'vpc_AVS_StateProv',
                                     :zip      => 'vpc_AVS_PostCode',
                                     :country  => 'vpc_AVS_Country'

          mapping :credit_card, :number             => 'vpc_CardNum',
                                :expiry_month       => 'vpc_CardExp',
                                :expiry_year        => 'vpc_CardExp',
                                :verification_value => 'vpc_CardSecurityCode',
                                :brand              => 'vpc_card'
        end
      end
    end
  end
end
