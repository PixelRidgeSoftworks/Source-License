# frozen_string_literal: true

# Source-License: Admin Categories Controller
# Handles product category management in the admin panel

module Admin::CategoriesController
  def self.setup_routes(app)
    # GET /admin/categories
    app.get '/admin/categories' do
      require_secure_admin_auth
      @categories = ProductCategory.order(:sort_order, :name)
      @stats = {
        total: @categories.count,
        active: @categories.where(active: true).count,
        inactive: @categories.where(active: false).count,
      }

      erb :'admin/categories', layout: :'layouts/admin_layout'
    end

    # GET /admin/categories/new
    app.get '/admin/categories/new' do
      require_secure_admin_auth
      @category = ProductCategory.new
      erb :'admin/categories_new', layout: :'layouts/admin_layout'
    end

    # POST /admin/categories
    app.post '/admin/categories' do
      require_secure_admin_auth
      @category = ProductCategory.new(category_params)

      begin
        @category.save_changes
        flash[:success] = "Category '#{@category.name}' created successfully."
        redirect '/admin/categories'
      rescue Sequel::ValidationFailed => e
        flash[:error] = "Failed to create category: #{e.message}"
        erb :'admin/categories_new', layout: :'layouts/admin_layout'
      rescue StandardError => e
        flash[:error] = "An error occurred: #{e.message}"
        erb :'admin/categories_new', layout: :'layouts/admin_layout'
      end
    end

    # GET /admin/categories/:id/edit
    app.get '/admin/categories/:id/edit' do
      require_secure_admin_auth
      @category = ProductCategory[params[:id]]
      return not_found unless @category

      erb :'admin/categories_edit', layout: :'layouts/admin_layout'
    end

    # PUT /admin/categories/:id
    app.put '/admin/categories/:id' do
      require_secure_admin_auth
      @category = ProductCategory[params[:id]]
      return not_found unless @category

      begin
        @category.update(category_params)
        flash[:success] = "Category '#{@category.name}' updated successfully."
        redirect '/admin/categories'
      rescue Sequel::ValidationFailed => e
        flash[:error] = "Failed to update category: #{e.message}"
        erb :'admin/categories_edit', layout: :'layouts/admin_layout'
      rescue StandardError => e
        flash[:error] = "An error occurred: #{e.message}"
        erb :'admin/categories_edit', layout: :'layouts/admin_layout'
      end
    end

    # DELETE /admin/categories/:id
    app.delete '/admin/categories/:id' do
      require_secure_admin_auth
      @category = ProductCategory[params[:id]]
      return not_found unless @category

      begin
        # Check if category has products
        product_count = @category.products.count

        if product_count.positive?
          halt 400,
               { success: false,
                 error: "Cannot delete category with #{product_count} associated products. Please reassign or delete the products first.", }.to_json
        end

        category_name = @category.name
        @category.destroy

        if request.xhr?
          content_type :json
          { success: true, message: "Category '#{category_name}' deleted successfully." }.to_json
        else
          flash[:success] = "Category '#{category_name}' deleted successfully."
          redirect '/admin/categories'
        end
      rescue StandardError => e
        if request.xhr?
          halt 500, { success: false, error: e.message }.to_json
        else
          flash[:error] = "Failed to delete category: #{e.message}"
          redirect '/admin/categories'
        end
      end
    end

    # POST /admin/categories/:id/toggle-status
    app.post '/admin/categories/:id/toggle-status' do
      require_secure_admin_auth
      @category = ProductCategory[params[:id]]
      return not_found unless @category

      begin
        new_status = params[:status] == 'active'
        @category.update(active: new_status)

        status_text = new_status ? 'activated' : 'deactivated'

        if request.xhr?
          content_type :json
          { success: true, message: "Category '#{@category.name}' #{status_text} successfully." }.to_json
        else
          flash[:success] = "Category '#{@category.name}' #{status_text} successfully."
          redirect '/admin/categories'
        end
      rescue StandardError => e
        if request.xhr?
          halt 500, { success: false, error: e.message }.to_json
        else
          flash[:error] = "Failed to update category: #{e.message}"
          redirect '/admin/categories'
        end
      end
    end

    # POST /admin/categories/bulk-action
    app.post '/admin/categories/bulk-action' do
      require_secure_admin_auth
      action = params[:action]
      category_ids = params[:category_ids]

      return halt(400, { success: false, error: 'No action specified' }.to_json) unless action
      return halt(400, { success: false, error: 'No categories selected' }.to_json) unless category_ids&.any?

      results = { success: 0, failed: 0, errors: [] }

      category_ids.each do |category_id|
        category = ProductCategory[category_id]
        next unless category

        case action
        when 'activate'
          category.update(active: true)
        when 'deactivate'
          category.update(active: false)
        when 'delete'
          if category.products.any?
            results[:errors] << "#{category.name}: Has associated products"
            results[:failed] += 1
            next
          end
          category.destroy
        else
          results[:errors] << "Unknown action: #{action}"
          results[:failed] += 1
          next
        end

        results[:success] += 1
      rescue StandardError => e
        results[:errors] << "#{category&.name || category_id}: #{e.message}"
        results[:failed] += 1
      end

      content_type :json
      { success: true, results: results }.to_json
    end

    # Helper method for category params
    def app.category_params
      {
        name: params[:name]&.strip,
        slug: params[:slug]&.strip,
        description: params[:description]&.strip,
        color: params[:color]&.strip,
        icon: params[:icon]&.strip,
        sort_order: params[:sort_order].to_i,
        active: %w[1 true].include?(params[:active]),
      }.compact
    end
  end
end
