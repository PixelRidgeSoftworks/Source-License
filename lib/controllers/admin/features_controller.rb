# frozen_string_literal: true

# This controller has been de-monolithed and its functionality moved to:
# - CustomerController: Customer management routes
# - ReportsController: Reports and analytics routes
# - CustomizationController: Template customization routes
# - OrderService: Shared order business logic
#
# The original order management routes were duplicated with the existing OrdersController,
# so they have been consolidated into the dedicated OrdersController.
#
# This file can be safely removed once all references are updated.

module AdminControllers::FeaturesController
  def self.included(base)
    base.include BaseController
    base.configure_controller
  end

  def self.setup_routes(app)
    # All routes have been moved to dedicated controllers:
    # - /admin/customers/* -> AdminControllers::CustomersController
    # - /admin/reports/* -> AdminControllers::ReportsController
    # - /admin/customize/* -> AdminControllers::CustomizationController
    # - /admin/orders/* -> Admin::OrdersController (existing)

    # This controller is now empty and ready for removal
  end
end
