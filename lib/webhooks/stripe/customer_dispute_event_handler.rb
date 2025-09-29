# frozen_string_literal: true

require_relative 'base_event_handler'
require_relative 'license_finder_service'
require_relative 'notification_service'

class Webhooks::Stripe::CustomerDisputeEventHandler < Webhooks::Stripe::BaseEventHandler
  class << self
    # Main entry point for customer and dispute events
    def handle_event(event)
      return { success: true, message: "Webhook #{event.type} is disabled" } unless webhook_enabled?(event.type)

      case event.type
      when 'customer.updated'
        handle_customer_updated(event)
      when 'charge.dispute.created'
        handle_dispute_created(event)
      when 'charge.dispute.updated'
        handle_dispute_updated(event)
      when 'charge.dispute.closed'
        handle_dispute_closed(event)
      else
        { success: true, message: "Unhandled customer/dispute event type: #{event.type}" }
      end
    end

    private

    def handle_customer_updated(event)
      customer = event.data.object

      # Update any licenses associated with this customer's email
      if customer.email
        licenses = License.where(customer_email: customer.email)
        licenses.each do |license|
          # Update customer name if provided
          next unless customer.name && customer.name != license.customer_name

          license.update(customer_name: customer.name)
          log_license_event(license, 'customer_updated', {
            customer_id: customer.id,
            old_name: license.customer_name,
            new_name: customer.name,
          })
        end
      end

      { success: true, message: 'Customer updated - license records synchronized' }
    end

    def handle_dispute_created(event)
      dispute = event.data.object
      charge = dispute.charge

      license = LicenseFinderService.find_license_for_charge_id(charge)
      return { success: false, error: 'License not found for disputed charge' } unless license

      DB.transaction do
        # Mark license as disputed (suspended but not revoked)
        license.update(status: 'disputed')

        log_license_event(license, 'dispute_created', {
          dispute_id: dispute.id,
          charge_id: charge,
          amount: dispute.amount / 100.0,
          reason: dispute.reason,
          status: dispute.status,
        })

        # Send dispute notification
        NotificationService.send_dispute_created_notification(license, dispute)
      end

      { success: true, message: 'Dispute created - license marked as disputed' }
    end

    def handle_dispute_updated(event)
      dispute = event.data.object
      charge = dispute.charge

      license = LicenseFinderService.find_license_for_charge_id(charge)
      return { success: false, error: 'License not found for disputed charge' } unless license

      log_license_event(license, 'dispute_updated', {
        dispute_id: dispute.id,
        charge_id: charge,
        status: dispute.status,
        evidence_due_by: dispute.evidence_details&.due_by,
      })

      { success: true, message: 'Dispute updated - logged for tracking' }
    end

    def handle_dispute_closed(event)
      dispute = event.data.object
      charge = dispute.charge

      license = LicenseFinderService.find_license_for_charge_id(charge)
      return { success: false, error: 'License not found for disputed charge' } unless license

      DB.transaction do
        case dispute.status
        when 'lost'
          # Dispute lost - revoke license
          license.revoke!
          log_license_event(license, 'dispute_lost_revoked', {
            dispute_id: dispute.id,
            charge_id: charge,
          })
          NotificationService.send_dispute_lost_notification(license, dispute)
        when 'won'
          # Dispute won - reactivate license if it was only disputed
          if license.status == 'disputed'
            license.reactivate!
            log_license_event(license, 'dispute_won_reactivated', {
              dispute_id: dispute.id,
              charge_id: charge,
            })
            NotificationService.send_dispute_won_notification(license, dispute)
          end
        end
      end

      { success: true, message: "Dispute #{dispute.status} - license status updated" }
    end
  end
end
