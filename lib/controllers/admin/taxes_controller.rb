# frozen_string_literal: true

# Source-License: Admin Taxes Controller
# Handles CRUD operations for tax management

class Admin::TaxesController < AdminController
  # List all taxes
  get '/admin/taxes' do
    @taxes = Tax.order(:name)
    @page_title = 'Tax Management'
    erb :'admin/taxes', layout: :'layouts/admin_layout'
  end

  # Show tax creation form
  get '/admin/taxes/new' do
    @tax = Tax.new
    @page_title = 'Create New Tax'
    erb :'admin/taxes_new', layout: :'layouts/admin_layout'
  end

  # Create new tax
  post '/admin/taxes' do
    @tax = Tax.new(tax_params)

    if @tax.valid? && @tax.save_changes
      flash[:success] = "Tax '#{@tax.name}' created successfully."
      redirect '/admin/taxes'
    else
      flash.now[:error] = "Failed to create tax: #{@tax.errors.full_messages.join(', ')}"
      erb :'admin/taxes_new', layout: :'layouts/admin_layout'
    end
  end

  # Show tax details
  get '/admin/taxes/:id' do
    @tax = Tax[params[:id]]
    halt 404, erb(:'errors/404', layout: :'layouts/admin_layout') unless @tax

    @page_title = "Tax: #{@tax.name}"
    erb :'admin/taxes_show', layout: :'layouts/admin_layout'
  end

  # Show tax edit form
  get '/admin/taxes/:id/edit' do
    @tax = Tax[params[:id]]
    halt 404, erb(:'errors/404', layout: :'layouts/admin_layout') unless @tax

    @page_title = "Edit Tax: #{@tax.name}"
    erb :'admin/taxes_edit', layout: :'layouts/admin_layout'
  end

  # Update tax
  put '/admin/taxes/:id' do
    @tax = Tax[params[:id]]
    halt 404, erb(:'errors/404', layout: :'layouts/admin_layout') unless @tax

    if @tax.update(tax_params)
      flash[:success] = "Tax '#{@tax.name}' updated successfully."
      redirect "/admin/taxes/#{@tax.id}"
    else
      flash.now[:error] = "Failed to update tax: #{@tax.errors.full_messages.join(', ')}"
      erb :'admin/taxes_edit', layout: :'layouts/admin_layout'
    end
  end

  # Delete tax
  delete '/admin/taxes/:id' do
    @tax = Tax[params[:id]]
    halt 404, erb(:'errors/404', layout: :'layouts/admin_layout') unless @tax

    # Check if tax is used in any orders
    orders_count = OrderTax.where(tax_id: @tax.id).count

    if orders_count.positive?
      flash[:error] =
        "Cannot delete tax '#{@tax.name}' because it has been used in #{orders_count} order(s). You can deactivate it instead."
    else
      tax_name = @tax.name
      @tax.delete
      flash[:success] = "Tax '#{tax_name}' deleted successfully."
    end
    redirect '/admin/taxes'
  end

  # Activate tax
  post '/admin/taxes/:id/activate' do
    @tax = Tax[params[:id]]
    halt 404, erb(:'errors/404', layout: :'layouts/admin_layout') unless @tax

    @tax.activate!
    flash[:success] = "Tax '#{@tax.name}' activated successfully."
    redirect '/admin/taxes'
  end

  # Deactivate tax
  post '/admin/taxes/:id/deactivate' do
    @tax = Tax[params[:id]]
    halt 404, erb(:'errors/404', layout: :'layouts/admin_layout') unless @tax

    @tax.deactivate!
    flash[:success] = "Tax '#{@tax.name}' deactivated successfully."
    redirect '/admin/taxes'
  end

  # API endpoint to get all active taxes
  get '/api/admin/taxes/active' do
    content_type :json

    taxes = Tax.active.map do |tax|
      {
        id: tax.id,
        name: tax.name,
        rate: tax.rate,
        formatted_rate: tax.formatted_rate,
        description: tax.description,
      }
    end

    { success: true, taxes: taxes }.to_json
  end

  # API endpoint to preview tax calculation
  post '/api/admin/taxes/preview' do
    content_type :json

    begin
      subtotal = params[:subtotal].to_f
      tax_ids = params[:tax_ids] || []

      return { success: false, error: 'Invalid subtotal amount' }.to_json if subtotal <= 0

      total_tax = 0.0
      tax_breakdown = []

      if tax_ids.empty?
        # Use all active taxes
        Tax.active.each do |tax|
          tax_amount = tax.calculate_amount(subtotal)
          next if tax_amount <= 0

          tax_breakdown << {
            name: tax.name,
            rate: tax.rate,
            amount: tax_amount,
            formatted_amount: "$#{format('%.2f', tax_amount)}",
          }

          total_tax += tax_amount
        end
      else
        # Use specific taxes
        Tax.where(id: tax_ids, status: 'active').each do |tax|
          tax_amount = tax.calculate_amount(subtotal)
          next if tax_amount <= 0

          tax_breakdown << {
            name: tax.name,
            rate: tax.rate,
            amount: tax_amount,
            formatted_amount: "$#{format('%.2f', tax_amount)}",
          }

          total_tax += tax_amount
        end
      end

      {
        success: true,
        subtotal: subtotal,
        formatted_subtotal: "$#{format('%.2f', subtotal)}",
        tax_total: total_tax,
        formatted_tax_total: "$#{format('%.2f', total_tax)}",
        total: subtotal + total_tax,
        formatted_total: "$#{format('%.2f', subtotal + total_tax)}",
        tax_breakdown: tax_breakdown,
      }.to_json
    rescue StandardError => e
      { success: false, error: e.message }.to_json
    end
  end

  private

  def tax_params
    {
      name: params[:name]&.strip,
      description: params[:description]&.strip,
      rate: params[:rate].to_f,
      status: params[:status] || 'active',
    }
  end
end
