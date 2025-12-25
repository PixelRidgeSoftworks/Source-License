# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/payments/paypal_processor'

class PaypalProcessorTest < Minitest::Test
  def test_verify_webhook_signature_delegates_and_returns_true_on_success
    payload = { id: 'evt_1' }.to_json
    headers = {
      'PAYPAL-TRANSMISSION-ID' => 'tx_1',
      'PAYPAL-TRANSMISSION-SIG' => 'sig',
      'PAYPAL-AUTH-ALGO' => 'SHA256',
      'PAYPAL-CERT-URL' => 'https://example.com/cert',
      'PAYPAL-TRANSMISSION-TIME' => Time.now.iso8601,
    }

    # Stub paypal_access_token and make_paypal_request
    Payments::PaypalProcessor.define_singleton_method(:paypal_access_token) { 'access-token' }
    Payments::PaypalProcessor.define_singleton_method(:make_paypal_request) do |_method, _endpoint, _data, _token|
      { 'verification_status' => 'SUCCESS' }
    end

    assert Payments::PaypalProcessor.verify_webhook_signature(payload, headers)
  end

  def test_verify_webhook_signature_returns_false_on_failure
    payload = { id: 'evt_2' }.to_json
    headers = { 'PAYPAL-TRANSMISSION-ID' => 'tx_2' }

    Payments::PaypalProcessor.define_singleton_method(:paypal_access_token) { 'access-token' }
    Payments::PaypalProcessor.define_singleton_method(:make_paypal_request) do |_m, _e, _d, _t|
      { 'verification_status' => 'FAILURE' }
    end

    refute Payments::PaypalProcessor.verify_webhook_signature(payload, headers)
  end
end
