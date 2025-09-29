# frozen_string_literal: true

# Admin Customization Controller
# Handles template customization and appearance management

module AdminControllers::CustomizationController
  def self.included(base)
    base.include BaseController
    base.configure_controller
  end

  def self.setup_routes(app)
    # Template customization main page
    app.get '/admin/customize' do
      require_secure_admin_auth
      @page_title = 'Template Customization'
      @categories = TemplateCustomizer.categories
      @customizations = TemplateCustomizer.all_customizations
      erb :'admin/customize', layout: :'layouts/admin_layout'
    end

    # Update customizations
    app.post '/admin/customize' do
      require_secure_admin_auth
      content_type :json

      begin
        updates = JSON.parse(request.body.read)
        TemplateCustomizer.update_multiple(updates)

        { success: true, message: 'Customizations saved successfully!' }.to_json
      rescue StandardError => e
        status 400
        { success: false, error: e.message }.to_json
      end
    end

    # Reset customizations to defaults
    app.post '/admin/customize/reset' do
      require_secure_admin_auth
      content_type :json

      begin
        TemplateCustomizer.reset_to_defaults
        { success: true, message: 'Customizations reset to defaults!' }.to_json
      rescue StandardError => e
        status 400
        { success: false, error: e.message }.to_json
      end
    end

    # Export customizations
    app.get '/admin/customize/export' do
      require_secure_admin_auth
      content_type 'application/x-yaml'
      attachment 'customizations.yml'
      TemplateCustomizer.export_customizations
    end

    # Import customizations
    app.post '/admin/customize/import' do
      require_secure_admin_auth
      content_type :json

      begin
        if params[:file] && params[:file][:tempfile]
          yaml_content = params[:file][:tempfile].read
          success = TemplateCustomizer.import_customizations(yaml_content)

          if success
            { success: true, message: 'Customizations imported successfully!' }.to_json
          else
            { success: false, error: 'Invalid YAML file format' }.to_json
          end
        else
          { success: false, error: 'No file uploaded' }.to_json
        end
      rescue StandardError => e
        status 400
        { success: false, error: e.message }.to_json
      end
    end

    # Template code guide
    app.get '/admin/customize/code-guide' do
      require_secure_admin_auth
      @page_title = 'Template Code Guide'
      erb :'admin/code_guide', layout: :'layouts/admin_layout'
    end

    # Live preview endpoint - Home Page
    app.get '/admin/customize/preview' do
      require_secure_admin_auth
      @page_title = custom('branding.site_name', 'Source License')
      @products = Product.where(active: true).order(:name).limit(3)
      erb :index, layout: :'layouts/main_layout'
    end

    # Live preview endpoint - Products Page
    app.get '/admin/customize/preview/products' do
      require_secure_admin_auth
      @page_title = custom('products_page.title', 'Our Software Products')
      @categories = ProductCategory.order(:name)
      @products = Product.where(active: true).order(:name)
      erb :products, layout: :'layouts/main_layout'
    end
  end
end
