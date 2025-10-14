# frozen_string_literal: true

require 'sinatra/base'
require 'yaml'
require 'json'

# Swagger UI Controller for API documentation
class SwaggerController < Sinatra::Base
  configure do
    set :views, File.expand_path('../../views', __dir__)
    set :public_folder, File.expand_path('../../public', __dir__)
    enable :sessions
    set :session_secret, ENV.fetch('SESSION_SECRET', SecureRandom.hex(32))
  end

  helpers do
    # Check if user is authenticated for Swagger access
    def authenticated?
      session[:swagger_authenticated] == true
    end

    # Require authentication for Swagger endpoints
    def require_swagger_auth
      return if authenticated?

      # Check for basic auth first
      auth = Rack::Auth::Basic::Request.new(request.env)
      if auth.provided? && auth.basic? && auth.credentials
        username, password = auth.credentials

        # Check against admin credentials or dedicated Swagger credentials
        if validate_swagger_credentials(username, password)
          session[:swagger_authenticated] = true
          return
        end
      end

      # If no valid auth, request basic auth
      response['WWW-Authenticate'] = 'Basic realm="Swagger API Documentation"'
      halt 401, {
        error: 'Authentication required',
        message: 'Please provide valid admin credentials to access API documentation',
        timestamp: Time.now.iso8601,
      }.to_json
    end

    # Validate credentials for Swagger access (admin credentials only)
    def validate_swagger_credentials(username, password)
      require_relative '../models'
      admin = Admin.first(email: username.strip.downcase)
      return false unless admin

      # Use BCrypt to verify password
      BCrypt::Password.new(admin.password_hash) == password
    rescue StandardError => e
      puts "Swagger auth error: #{e.message}" if ENV['APP_ENV'] == 'development'
      false
    end

    # Logout from Swagger
    def swagger_logout
      session[:swagger_authenticated] = nil
    end
  end

  # Authentication endpoint for Swagger
  get '/docs/login' do
    if authenticated?
      redirect '/docs'
    else
      content_type 'text/html'
      erb :swagger_login
    end
  end

  # Handle login form submission
  post '/docs/login' do
    username = params[:username]
    password = params[:password]

    if validate_swagger_credentials(username, password)
      session[:swagger_authenticated] = true
      redirect '/docs'
    else
      @error = 'Invalid credentials'
      erb :swagger_login
    end
  end

  # Logout endpoint
  post '/docs/logout' do
    swagger_logout
    redirect '/docs/login'
  end

  # Serve the main Swagger UI page
  get '/docs' do
    require_swagger_auth
    erb :swagger_ui
  end

  # Serve the OpenAPI specification as JSON
  get '/docs/openapi.json' do
    require_swagger_auth
    content_type 'application/json'

    begin
      # Load the YAML specification
      yaml_path = File.expand_path('../../swagger/license_api.yml', __dir__)
      yaml_content = File.read(yaml_path)
      openapi_spec = YAML.safe_load(yaml_content)

      # Convert to JSON and return
      openapi_spec.to_json
    rescue StandardError => e
      status 500
      {
        error: 'Failed to load API specification',
        details: e.message,
        timestamp: Time.now.iso8601,
      }.to_json
    end
  end

  # Serve the OpenAPI specification as YAML
  get '/docs/openapi.yml' do
    require_swagger_auth
    content_type 'application/x-yaml'

    begin
      yaml_path = File.expand_path('../../swagger/license_api.yml', __dir__)
      File.read(yaml_path)
    rescue StandardError => e
      status 500
      "error: Failed to load API specification\ndetails: #{e.message}\ntimestamp: #{Time.now.iso8601}"
    end
  end

  # API documentation redirect
  get '/api-docs' do
    redirect '/docs'
  end

  # API specification metadata
  get '/docs/info' do
    require_swagger_auth
    content_type 'application/json'

    begin
      yaml_path = File.expand_path('../../swagger/license_api.yml', __dir__)
      yaml_content = File.read(yaml_path)
      openapi_spec = YAML.safe_load(yaml_content)

      {
        title: openapi_spec['info']['title'],
        version: openapi_spec['info']['version'],
        description: openapi_spec['info']['description'],
        contact: openapi_spec['info']['contact'],
        license: openapi_spec['info']['license'],
        servers: openapi_spec['servers'],
        tags: openapi_spec['tags']&.map { |tag| { name: tag['name'], description: tag['description'] } },
        paths_count: openapi_spec['paths']&.keys&.length || 0,
        schemas_count: openapi_spec['components']&.dig('schemas')&.keys&.length || 0,
        timestamp: Time.now.iso8601,
      }.to_json
    rescue StandardError => e
      status 500
      {
        error: 'Failed to load API information',
        details: e.message,
        timestamp: Time.now.iso8601,
      }.to_json
    end
  end

  # Health check for documentation service
  get '/docs/health' do
    content_type 'application/json'

    checks = {}
    overall_status = 200

    # Check if OpenAPI spec file exists and is valid
    begin
      yaml_path = File.expand_path('../../swagger/license_api.yml', __dir__)

      if File.exist?(yaml_path)
        yaml_content = File.read(yaml_path)
        openapi_spec = YAML.safe_load(yaml_content)

        if openapi_spec.is_a?(Hash) && openapi_spec['openapi']
          checks[:openapi_spec] = {
            status: 'ok',
            message: 'OpenAPI specification loaded successfully',
            version: openapi_spec['info']['version'],
          }
        else
          checks[:openapi_spec] = {
            status: 'error',
            message: 'Invalid OpenAPI specification format',
          }
          overall_status = 503
        end
      else
        checks[:openapi_spec] = {
          status: 'error',
          message: 'OpenAPI specification file not found',
        }
        overall_status = 503
      end
    rescue StandardError => e
      checks[:openapi_spec] = {
        status: 'error',
        message: "Failed to load OpenAPI specification: #{e.message}",
      }
      overall_status = 503
    end

    # Check if Swagger UI template exists
    begin
      template_path = File.expand_path('../../views/swagger_ui.erb', __dir__)
      checks[:swagger_ui] = if File.exist?(template_path)
                              {
                                status: 'ok',
                                message: 'Swagger UI template available',
                              }
                            else
                              {
                                status: 'warning',
                                message: 'Swagger UI template not found',
                              }
                            end
    rescue StandardError => e
      checks[:swagger_ui] = {
        status: 'error',
        message: "Failed to check Swagger UI template: #{e.message}",
      }
    end

    # Check if public assets directory exists
    begin
      public_path = File.expand_path('../../public', __dir__)
      checks[:public_assets] = if Dir.exist?(public_path)
                                 {
                                   status: 'ok',
                                   message: 'Public assets directory available',
                                 }
                               else
                                 {
                                   status: 'warning',
                                   message: 'Public assets directory not found',
                                 }
                               end
    rescue StandardError => e
      checks[:public_assets] = {
        status: 'error',
        message: "Failed to check public assets: #{e.message}",
      }
    end

    status overall_status
    {
      status: overall_status == 200 ? 'healthy' : 'unhealthy',
      service: 'swagger-documentation',
      version: '1.0.0',
      timestamp: Time.now.iso8601,
      checks: checks,
    }.to_json
  end

  # Handle 404 for documentation routes
  not_found do
    content_type 'application/json'
    status 404
    {
      error: 'Documentation endpoint not found',
      available_endpoints: [
        '/docs - Swagger UI interface',
        '/docs/openapi.json - OpenAPI specification (JSON)',
        '/docs/openapi.yml - OpenAPI specification (YAML)',
        '/docs/info - API information summary',
        '/docs/health - Documentation service health',
      ],
      timestamp: Time.now.iso8601,
    }.to_json
  end

  # Error handler
  error do
    content_type 'application/json'
    status 500
    {
      error: 'Documentation service error',
      timestamp: Time.now.iso8601,
    }.to_json
  end
end
