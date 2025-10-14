# frozen_string_literal: true

# Source-License: Billing Address Model
# Handles customer billing addresses with validation and management features

class BillingAddress < Sequel::Model
  # Associations
  many_to_one :user

  # Validations
  def validate
    super
    validates_presence %i[user_id name first_name last_name address_line_1 city state_province
                          postal_code country]
    validates_max_length 255, :name
    validates_max_length 100, %i[first_name last_name company city state_province country]
    validates_max_length 255, %i[address_line_1 address_line_2]
    validates_max_length 20, %i[postal_code phone]

    # Validate country format
    validates_format(/^[a-zA-Z\s\-']+$/, :country,
                     message: 'must contain only letters, spaces, hyphens, and apostrophes')

    # Validate postal code format (basic validation)
    validates_format(/^[a-zA-Z0-9\s-]+$/, :postal_code,
                     message: 'must contain only letters, numbers, spaces, and hyphens')

    # Validate phone format if provided
    return unless phone && !phone.empty?

    validates_format(/^[\d\s\-+().]+$/, :phone, message: 'must be a valid phone number format')
  end

  # Hooks
  def before_save
    super
    self.updated_at = Time.now

    # Ensure only one default address per user
    return unless is_default

    BillingAddress.where(user_id: user_id, is_default: true)
      .exclude(id: id)
      .update(is_default: false)
  end

  # Instance methods
  def full_name
    "#{first_name} #{last_name}".strip
  end

  def full_address
    parts = [address_line_1]
    parts << address_line_2 if address_line_2 && !address_line_2.empty?
    parts << city
    parts << state_province
    parts << postal_code
    parts << country
    parts.join(', ')
  end

  def single_line_address
    parts = []
    parts << address_line_1
    parts << address_line_2 if address_line_2 && !address_line_2.empty?
    parts << "#{city}, #{state_province} #{postal_code}"
    parts << country
    parts.join(', ')
  end

  def formatted_address_html
    html_parts = []
    html_parts << "<strong>#{escape_html(full_name)}</strong>"
    html_parts << escape_html(company) if company && !company.empty?
    html_parts << escape_html(address_line_1)
    html_parts << escape_html(address_line_2) if address_line_2 && !address_line_2.empty?
    html_parts << "#{escape_html(city)}, #{escape_html(state_province)} #{escape_html(postal_code)}"
    html_parts << escape_html(country)
    html_parts << escape_html(phone) if phone && !phone.empty?

    html_parts.join('<br>').html_safe
  end

  def to_hash
    {
      id: id,
      name: name,
      first_name: first_name,
      last_name: last_name,
      full_name: full_name,
      company: company,
      address_line_1: address_line_1,
      address_line_2: address_line_2,
      city: city,
      state_province: state_province,
      postal_code: postal_code,
      country: country,
      phone: phone,
      is_default: is_default,
      single_line_address: single_line_address,
      created_at: created_at,
      updated_at: updated_at,
    }
  end

  # Class methods
  def self.for_user(user_id)
    where(user_id: user_id).order(:is_default.desc, :name)
  end

  def self.default_for_user(user_id)
    where(user_id: user_id, is_default: true).first
  end

  def self.create_for_user(user_id, params)
    # Clean up parameters
    clean_params = {
      user_id: user_id,
      name: params[:name]&.strip,
      first_name: params[:first_name]&.strip,
      last_name: params[:last_name]&.strip,
      company: params[:company]&.strip,
      address_line_1: params[:address_line_1]&.strip,
      address_line_2: params[:address_line_2]&.strip,
      city: params[:city]&.strip,
      state_province: params[:state_province]&.strip,
      postal_code: params[:postal_code]&.strip&.upcase,
      country: params[:country]&.strip,
      phone: params[:phone]&.strip,
      is_default: params[:is_default] || false,
    }

    # Remove empty optional fields
    clean_params.delete(:company) if clean_params[:company].nil? || clean_params[:company].empty?
    clean_params.delete(:address_line_2) if clean_params[:address_line_2].nil? || clean_params[:address_line_2].empty?
    clean_params.delete(:phone) if clean_params[:phone].nil? || clean_params[:phone].empty?

    # If this is the user's first address, make it default
    existing_count = where(user_id: user_id).count
    clean_params[:is_default] = true if existing_count.zero?

    create(clean_params)
  end

  def self.update_address(address_id, user_id, params)
    address = where(id: address_id, user_id: user_id).first
    return nil unless address

    # Clean up parameters
    clean_params = {
      name: params[:name]&.strip,
      first_name: params[:first_name]&.strip,
      last_name: params[:last_name]&.strip,
      company: params[:company]&.strip,
      address_line_1: params[:address_line_1]&.strip,
      address_line_2: params[:address_line_2]&.strip,
      city: params[:city]&.strip,
      state_province: params[:state_province]&.strip,
      postal_code: params[:postal_code]&.strip&.upcase,
      country: params[:country]&.strip,
      phone: params[:phone]&.strip,
      is_default: params[:is_default] || false,
    }

    # Remove empty optional fields
    clean_params[:company] = nil if clean_params[:company].nil? || clean_params[:company].empty?
    clean_params[:address_line_2] = nil if clean_params[:address_line_2].nil? || clean_params[:address_line_2].empty?
    clean_params[:phone] = nil if clean_params[:phone].nil? || clean_params[:phone].empty?

    address.update(clean_params)
    address
  end

  def self.delete_for_user(address_id, user_id)
    address = where(id: address_id, user_id: user_id).first
    return false unless address

    # Don't allow deletion of default address if it's the only one
    if address.is_default
      other_addresses = where(user_id: user_id).exclude(id: address_id)
      if other_addresses.any?
        # Make the first other address the new default
        other_addresses.first.update(is_default: true)
      elsif other_addresses.none?
        # This is the last address, don't delete it
        return false
      end
    end

    address.delete
    true
  end

  private

  def escape_html(text)
    return '' unless text

    text.to_s.gsub(/[&<>"']/) do |char|
      case char
      when '&' then '&amp;'
      when '<' then '&lt;'
      when '>' then '&gt;'
      when '"' then '&quot;'
      when "'" then '&#x27;'
      end
    end
  end
end
