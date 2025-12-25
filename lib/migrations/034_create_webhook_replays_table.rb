# frozen_string_literal: true

# Source-License: Migration 34 - Create Webhook Replays Table
# Creates a durable table to record processed webhooks to prevent replay attacks

class Migrations::CreateWebhookReplaysTable < Migrations::BaseMigration
  VERSION = 34

  def up
    DB.create_table :webhook_replays do
      primary_key :id
      String :provider, size: 50, null: false
      String :transmission_id, size: 255, null: false
      String :event_id, size: 255
      DateTime :processed_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :provider
      index :event_id
      unique %i[provider transmission_id]
    end
  end
end
