# frozen_string_literal: true

require_relative 'base_model_methods'
require 'sequel'
require 'json'

# Products available for purchase
class Product < Sequel::Model
  include BaseModelMethods

  set_dataset :products
  one_to_many :order_items
  one_to_many :licenses

  # Parse features from JSON
  def features_list
    return [] unless features

    JSON.parse(features)
  rescue JSON::ParserError
    []
  end

  # Set features as JSON
  def features_list=(list)
    self.features = list.to_json
  end

  # Check if product is subscription-based
  def subscription?
    license_type == 'subscription'
  end

  # Check if product is one-time purchase
  def one_time?
    license_type == 'one_time'
  end

  # Get formatted price
  def formatted_price
    "$#{format('%.2f', price)}"
  end

  # Get download file path
  def download_file_path
    return nil unless download_file

    File.join(ENV['DOWNLOADS_PATH'] || './downloads', download_file)
  end

  # Check if download file exists
  def download_file_exists?
    return false unless download_file

    File.exist?(download_file_path)
  end

  # Get billing cycle object
  def billing_cycle_object
    return nil unless billing_cycle

    BillingCycle.by_name(billing_cycle)
  end

  # Get formatted setup fee
  def formatted_setup_fee
    return nil unless setup_fee&.positive?

    "$#{format('%.2f', setup_fee)}"
  end

  # Get total first payment (price + setup fee)
  def total_first_payment
    base_price = price || 0
    fee = setup_fee || 0
    base_price + fee
  end

  # Get formatted total first payment
  def formatted_total_first_payment
    "$#{format('%.2f', total_first_payment)}"
  end

  # Check if product has trial period
  def trial?
    trial_period_days&.positive?
  end

  # Get trial period text
  def trial_period_text
    return 'No trial' unless has_trial?

    if trial_period_days == 1
      '1 day trial'
    elsif trial_period_days < 30
      "#{trial_period_days} day trial"
    elsif trial_period_days == 30
      '1 month trial'
    else
      months = trial_period_days / 30
      remainder = trial_period_days % 30
      if remainder.zero?
        "#{months} month trial"
      else
        "#{months} month, #{remainder} day trial"
      end
    end
  end

  # Get billing frequency text
  def billing_frequency_text
    cycle = billing_cycle_object
    return 'One-time payment' unless cycle

    interval = billing_interval || 1
    if interval == 1
      cycle.display_name
    else
      "Every #{interval} #{cycle.display_name.downcase}"
    end
  end

  # Calculate next billing date from a start date
  def next_billing_date(from_date = Time.now)
    cycle = billing_cycle_object
    return nil unless cycle

    interval = billing_interval || 1
    cycle.next_billing_date(from_date + ((interval - 1) * cycle.days * 24 * 60 * 60))
  end

  # Validation
  def validate
    super
    errors.add(:name, 'cannot be empty') if !name || name.strip.empty?
    errors.add(:price, 'must be greater than or equal to 0') if !price || price.negative?
    errors.add(:license_type, 'must be one_time or subscription') unless %w[one_time
                                                                            subscription].include?(license_type)
    errors.add(:max_activations, 'must be greater than 0') if !max_activations || max_activations <= 0

    return unless subscription? && (!license_duration_days || license_duration_days <= 0)

    errors.add(:license_duration_days, 'must be set for subscription products')
  end
end
