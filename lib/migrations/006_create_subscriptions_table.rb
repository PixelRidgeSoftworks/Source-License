# frozen_string_literal: true

# Source-License: Migration 6 - Create Subscriptions Table
# Creates the subscriptions table for subscription-based licenses

class Migrations::CreateSubscriptionsTable < BaseMigration
  VERSION = 6

  def up
    DB.create_table :subscriptions do
      primary_key :id
      foreign_key :license_id, :licenses, null: false, on_delete: :cascade
      String :external_subscription_id, size: 255 # Stripe/PayPal subscription ID
      String :status, null: false, default: 'active' # active, canceled, past_due, unpaid
      DateTime :current_period_start, null: false
      DateTime :current_period_end, null: false
      DateTime :canceled_at
      Boolean :auto_renew, default: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :license_id
      index :external_subscription_id
      index :status
    end
  end
end
