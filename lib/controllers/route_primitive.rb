# frozen_string_literal: true

# Base class for defining individual routes as separate, testable units
# This allows controllers to break down complex setup_routes methods into
# smaller, manageable route primitives
class RoutePrimitive
  attr_reader :app, :method, :path

  def initialize(app, method, path)
    @app = app
    @method = method.to_s.upcase
    @path = path
  end

  # Register this route with the Sinatra app
  def register!
    case @method
    when 'GET'
      @app.get(@path, &method(:handle))
    when 'POST'
      @app.post(@path, &method(:handle))
    when 'PUT'
      @app.put(@path, &method(:handle))
    when 'PATCH'
      @app.patch(@path, &method(:handle))
    when 'DELETE'
      @app.delete(@path, &method(:handle))
    else
      raise "Unsupported HTTP method: #{@method}"
    end
  end

  # Override this method in subclasses to implement route logic
  def handle
    raise NotImplementedError, "Subclasses must implement the 'handle' method"
  end

  # Convenience method to access current Sinatra context
  def sinatra_context
    @app
  end

  # Delegate common Sinatra methods to the app context
  def params
    sinatra_context.params
  end

  def request
    sinatra_context.request
  end

  def response
    sinatra_context.response
  end

  def session
    sinatra_context.session
  end

  def halt(*)
    sinatra_context.halt(*)
  end

  def status(code)
    sinatra_context.status(code)
  end

  def content_type(type)
    sinatra_context.content_type(type)
  end

  # Helper method for JSON responses
  def json_response(data, status_code = 200)
    content_type :json
    status(status_code)
    data.to_json
  end

  # Helper method for error responses
  def error_response(message, status_code = 400)
    json_response({ success: false, error: message }, status_code)
  end

  # Helper method for success responses
  def success_response(data = {}, message = nil)
    response_data = { success: true }
    response_data[:message] = message if message
    response_data.merge!(data) if data.is_a?(Hash)
    json_response(response_data)
  end

  # Helper method to parse JSON request body
  def parse_json_body
    request.body.rewind
    JSON.parse(request.body.read, symbolize_names: true)
  rescue JSON::ParserError
    nil
  end

  # Class method to create and register a route primitive
  def self.register_route(app, method, path, &)
    route_class = Class.new(RoutePrimitive) do
      define_method(:handle, &)
    end

    route = route_class.new(app, method, path)
    route.register!
    route
  end
end
