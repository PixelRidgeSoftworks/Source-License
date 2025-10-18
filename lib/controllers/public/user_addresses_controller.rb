# frozen_string_literal: true

require_relative '../core/route_primitive'

# Controller for user billing address management
module UserAddressesController
  def self.setup_routes(app)
    get_addresses_route(app)
    get_address_route(app)
    create_address_route(app)
    update_address_route(app)
    delete_address_route(app)
    set_default_address_route(app)
  end

  # Get all addresses for current user
  def self.get_addresses_route(app)
    app.get '/api/user/addresses' do
      halt(401, { error: 'Authentication required' }.to_json) unless current_user
      content_type :json

      begin
        addresses = BillingAddress.for_user(current_user.id)
        addresses_data = addresses.map(&:to_hash)
        addresses_data.to_json
      rescue StandardError => e
        status 500
        { error: e.message }.to_json
      end
    end
  end

  # Get specific address for current user
  def self.get_address_route(app)
    app.get '/api/user/addresses/:id' do
      halt(401, { error: 'Authentication required' }.to_json) unless current_user
      content_type :json

      begin
        address = BillingAddress.where(id: params[:id], user_id: current_user.id).first
        if address
          address.to_hash.to_json
        else
          status 404
          { error: 'Address not found' }.to_json
        end
      rescue StandardError => e
        status 500
        { error: e.message }.to_json
      end
    end
  end

  # Create new address for current user
  def self.create_address_route(app)
    app.post '/api/user/addresses' do
      halt(401, { error: 'Authentication required' }.to_json) unless current_user
      content_type :json

      begin
        request.body.rewind
        address_data = JSON.parse(request.body.read, symbolize_names: true)

        address = BillingAddress.create_for_user(current_user.id, address_data)

        if address.valid?
          address.to_hash.to_json
        else
          status 400
          { error: address.errors.full_messages.join(', ') }.to_json
        end
      rescue JSON::ParserError
        status 400
        { error: 'Invalid JSON data' }.to_json
      rescue StandardError => e
        status 500
        { error: e.message }.to_json
      end
    end
  end

  # Update existing address for current user
  def self.update_address_route(app)
    app.put '/api/user/addresses/:id' do
      halt(401, { error: 'Authentication required' }.to_json) unless current_user
      content_type :json

      begin
        request.body.rewind
        address_data = JSON.parse(request.body.read, symbolize_names: true)

        address = BillingAddress.update_address(params[:id], current_user.id, address_data)

        if address&.valid?
          address.to_hash.to_json
        elsif address
          status 400
          { error: address.errors.full_messages.join(', ') }.to_json
        else
          status 404
          { error: 'Address not found' }.to_json
        end
      rescue JSON::ParserError
        status 400
        { error: 'Invalid JSON data' }.to_json
      rescue StandardError => e
        status 500
        { error: e.message }.to_json
      end
    end
  end

  # Delete address for current user
  def self.delete_address_route(app)
    app.delete '/api/user/addresses/:id' do
      halt(401, { error: 'Authentication required' }.to_json) unless current_user
      content_type :json

      begin
        success = BillingAddress.delete_for_user(params[:id], current_user.id)

        if success
          { success: true, message: 'Address deleted successfully' }.to_json
        else
          status 400
          { error: 'Cannot delete address. It may be your only address or the default address.' }.to_json
        end
      rescue StandardError => e
        status 500
        { error: e.message }.to_json
      end
    end
  end

  # Set address as default
  def self.set_default_address_route(app)
    app.patch '/api/user/addresses/:id/set_default' do
      halt(401, { error: 'Authentication required' }.to_json) unless current_user
      content_type :json

      begin
        address = BillingAddress.where(id: params[:id], user_id: current_user.id).first

        if address
          # Remove default from other addresses
          BillingAddress.where(user_id: current_user.id, is_default: true)
            .exclude(id: address.id)
            .update(is_default: false)

          # Set this address as default
          address.update(is_default: true)

          { success: true, message: 'Default address updated' }.to_json
        else
          status 404
          { error: 'Address not found' }.to_json
        end
      rescue StandardError => e
        status 500
        { error: e.message }.to_json
      end
    end
  end
end
